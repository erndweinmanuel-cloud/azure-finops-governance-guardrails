targetScope = 'subscription'

param budgetName string
param amount int
param startDate string
param endDate string
param actionGroupId string
param locale string = 'de-de'

resource budget 'Microsoft.Consumption/budgets@2024-08-01' = {
  name: budgetName
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
      endDate: endDate
    }
    notifications: {
      actual_GTE_50: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 50
        contactGroups: [ actionGroupId ]
        locale: locale
      }
      actual_GTE_80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactGroups: [ actionGroupId ]
        locale: locale
      }
      actual_GTE_100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactGroups: [ actionGroupId ]
        locale: locale
      }
    }
  }
}
