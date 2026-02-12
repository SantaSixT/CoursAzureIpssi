param location string = 'spaincentral'
// Génère un suffixe unique
param uniqueSuffix string = uniqueString(resourceGroup().id)

// Configuration StorageV2, Standard, LRS [cite: 26, 27]
var storageSettings = {
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Enabled' 
    allowBlobPublicAccess: false // Accès public désactivé [cite: 28]
  }
}

// 1. Compte de stockage Principal (Nom raccourci) [cite: 32]
resource storagePrimary 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'stprim${uniqueSuffix}' 
  location: location
  sku: storageSettings.sku
  kind: storageSettings.kind
  properties: storageSettings.properties
}

// 2. Compte de stockage Secondaire [cite: 32]
resource storageSecondary 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'stsec${uniqueSuffix}' 
  location: location
  sku: storageSettings.sku
  kind: storageSettings.kind
  properties: storageSettings.properties
}

// 3. Container 'documents' (Mode Private) [cite: 29, 32]
resource primaryContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storagePrimary.name}/default/documents'
  properties: {
    publicAccess: 'None' 
  }
}

resource secondaryContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageSecondary.name}/default/documents'
  properties: {
    publicAccess: 'None' 
  }
}
