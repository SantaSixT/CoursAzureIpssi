param location string = resourceGroup().location
param adminUsername string = 'azureuser'
param adminPassword string = 'P@ssword1234!' // À changer si nécessaire

// 1. Réseau et Sous-réseau 
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-poc'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'default'
        properties: { addressPrefix: '10.0.1.0/24' }
      }
    ]
  }
}

// 2. IP Publique pour le Load Balancer [cite: 9]
resource lbPublicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'pip-lb'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

// 3. Load Balancer [cite: 9]
resource lb 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: 'lb-poc'
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'lb-frontend'
        properties: { publicIPAddress: { id: lbPublicIP.id } }
      }
    ]
    backendAddressPools: [ { name: 'backend-pool' } ] // [cite: 10]
    probes: [
      {
        name: 'http-probe' // 
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'http-rule' // [cite: 12]
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-poc', 'lb-frontend') }
          backendAddressPool: { id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-poc', 'backend-pool') }
          probe: { id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-poc', 'http-probe') }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
        }
      }
    ]
  }
}

// 4. Déploiement des 2 VM [cite: 7]
resource nics 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(0, 2): {
  name: 'nic-vm-${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          loadBalancerBackendAddressPools: [ { id: lb.properties.backendAddressPools[0].id } ]
        }
      }
    ]
  }
}]

resource vms 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0, 2): {
  name: 'vm-linux-${i}'
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_D2s_V3' }
    osProfile: {
      computerName: 'vm-linux-${i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      // Installation automatique du serveur web [cite: 8]
      customData: base64('apt-get update && apt-get install -y apache2 && echo "Hello from VM ${i}" > /var/www/html/index.html')
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [ { id: nics[i].id } ]
    }
  }
}]
