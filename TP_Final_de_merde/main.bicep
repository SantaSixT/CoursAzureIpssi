param location string = 'francecentral'
param adminUsername string = 'azureuser'
@secure()
param sshPublicKey string
param emailForAlerts string = 'a.rohrbasser@ecole-ipssi.net'

// 1. Réseau & Load Balancer
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-tp'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [{ name: 'snet-web', properties: { addressPrefix: '10.0.1.0/24' } }]
  }
}

resource lbPublicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-lb'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2023-05-01' = {
  name: 'lb-web'
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [{ name: 'lb-front', properties: { publicIPAddress: { id: lbPublicIP.id } } }]
    backendAddressPools: [{ name: 'BackendPool' }]
    probes: [{ name: 'http-probe', properties: { protocol: 'Http', port: 80, requestPath: '/' } }]
    loadBalancingRules: [{
        name: 'http-rule'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-web', 'lb-front') }
          backendAddressPool: { id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-web', 'BackendPool') }
          probe: { id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-web', 'http-probe') }
          protocol: 'Tcp', frontendPort: 80, backendPort: 80
        }
    }]
  }
}

// 2. Disponibilité & Calcul
resource avSet 'Microsoft.Compute/availabilitySets@2023-03-01' = {
  name: 'avset-web'
  location: location
  sku: { name: 'Aligned' }
  properties: { platformFaultDomainCount: 2, platformUpdateDomainCount: 2 }
}

resource nics 'Microsoft.Network/networkInterfaces@2023-05-01' = [for i in range(0, 2): {
  name: 'nic-vm-${i}'
  location: location
  properties: {
    ipConfigurations: [{
        name: 'ipconfig'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          loadBalancerBackendAddressPools: [{ id: loadBalancer.properties.backendAddressPools[0].id }]
        }
    }]
  }
}]

resource vms 'Microsoft.Compute/virtualMachines@2023-03-01' = [for i in range(0, 2): {
  name: 'vm-web-${i}'
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_D2s_V3' }
    availabilitySet: { id: avSet.id }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: '0001-com-ubuntu-server-jammy', sku: '22_04-lts', version: 'latest' }
      osDisk: { createOption: 'FromImage', managedDisk: { storageAccountType: 'StandardSSD_LRS' } }
    }
    osProfile: {
      computerName: 'vm-web-${i}'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: { publicKeys: [{ path: '/home/${adminUsername}/.ssh/authorized_keys', keyData: sshPublicKey }] }
      }
    }
    networkProfile: { networkInterfaces: [{ id: nics[i].id }] }
  }
}]

// 3. Installation Automatique Serveur Web (Point 4.20)
resource installApache 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = [for i in range(0, 2): {
  name: 'vm-web-${i}/install-apache'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    settings: {
      commandToExecute: 'sudo apt-get update && sudo apt-get install -y apache2 && echo "<h1>Serveur ${i} opérationnel</h1>" | sudo tee /var/www/html/index.html'
    }
  }
  dependsOn: [ vms ]
}]

// 4. Alertes & Monitoring (Point 4.28)
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-admin'
  location: 'Global'
  properties: {
    groupShortName: 'AlertAdmin'
    enabled: true
    emailReceivers: [{ name: 'admin-email', emailAddress: emailForAlerts, useCommonAlertSchema: true }]
  }
}

resource vmAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = [for i in range(0, 2): {
  name: 'alert-vm-down-${i}'
  location: 'Global'
  properties: {
    description: 'Alerte si la VM ${i} est arrêtée'
    severity: 2
    enabled: true
    scopes: [ vms[i].id ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [{
          name: 'HeartbeatCheck'
          metricName: 'Percentage CPU' // On surveille le CPU comme proxy d'activité
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
      }]
    }
    actions: [{ actionGroupId: actionGroup.id }]
  }
}]

// 5. Budget (Point 4.28 suite)
resource budget 'Microsoft.Consumption/budgets@2021-10-01' = {
  name: 'tp-budget'
  // On ne définit pas le scope explicitement ici car il hérite du groupe de ressources par défaut
  properties: {
    amount: 50
    category: 'Cost'
    timeGrain: 'Monthly'
    timePeriod: { 
      startDate: '2026-02-01' // Assure-toi que la date est actuelle (2026)
      endDate: '2028-12-31' 
    }
    notifications: {
      Actual_80_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: [ emailForAlerts ]
      }
    }
  }
}
