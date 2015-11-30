# PowerColleague

**PowerColleague** is a PowerShell module and wrapper around Colleague's *.Net SDK*

## Before Use
- Verify that Visual Studio is installed *I haven't tested this without a VS installation*
- Verify which version of the the Colleague .Net SDK is installed 

## Install
1. Clone this project 
```
git clone https://github.com/TOAD-CODE/PowerColleague
```
2. Move the `PowerColleague` folder to your module folder
  *To find modules run:* 
```powershell
$env:PSModulePath -split ";"
```

## Setup for first use
1. Update the file `defaultVersion` with the correct Colleague .Net SDK version that is installed
  *Note:* Current default is 1.6 but I've tested it in 1.5 through 1.8
2. Select the folder that corresponds to the value listed in `defaultVersion`
3. Update the App.config file in the selected folder with your information.
  - Colleague Username
  - Colleague Password
  - Colleague Environment Name
  - Colleague Environment Address
  - Colleague Environment Port Number
  - Colleague Environment Shared Secret

## Usage
Import the PowerShell Module
```powershell
Import-Module PowerColleague
```

### Read Colleague Entities
  To read information from Colleague Entities call see the examples below:
```powershell
Read-TableInfo Person -Filter "LAST.NAME EQ 'Garrison'" | Select FirstName, LastName
```
  FirstName|LastName
  ---------|--------
  ...|...
  Roger|Garrison
  ...|...

```powershell
Read-TableKeys Person -Filter "LAST.NAME EQ 'Garrison' AND FIRST.NAME EQ 'Roger'" 
```

### Execute Colleague Transactions
  *Note:* I'm working to clean this up a bit
  - Generate the transaction and compile it in memory
```powershell
Set-DataContract (Get-CTXModel ST SFX007) StartStudentPaymentRequest
```
  - Create a new Transaction Request
```powershell
$request = New-Object ColleagueSDK.DataContracts.StartStudentPaymentRequest
```
  - Set the Request Variables
```powershell
$request.InPersonId = $PersonId
```
  - Invoke the Transaction
```powershell
$response = InvokeCTX $request.getType() (New-Object ColleagueSDK.DataContracts.StartStudentPaymentResponse).getType() $request
```
  
### Find All Colleague Entities in all Applications
```powershell
Get-AllApplications | Get-ApplicationEntities
```

### Find All Colleague Transactions in all Applications
```powershell
Get-AllApplications | Get-ApplicationCtxs
```
  
### Find which Application has an Entity
```powershell
Get-AppsForEntity Person
```
`CORE`



*Tested:* PowerShell v4.0
