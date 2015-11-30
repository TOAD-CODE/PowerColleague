# PowerColleague

**PowerColleague** is a PowerShell module and wrapper around Colleague's *.Net SDK*

## Before Use
- Verify that Visual Studio is installed 
  *I haven't tested this without a VS installation*
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
$response = Invoke-CTX $request.getType() (New-Object ColleagueSDK.DataContracts.StartStudentPaymentResponse).getType() $request
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
*Returns `CORE`

### All Other commands
Command|Synopsis
----|--------
```powershell
Close-DmiSession
```|Close the Dmi Session 
Get-AllApplications|Get all Colleague Applications
Get-ApplicationCtxs|Get all the Transactions for a given Colleague Application
Get-ApplicationEntities|Get all the Entities for a given Colleague Application
Get-AppsForEntity|Get all Colleague Applications that contain a given Entity
Get-ColleagueEnv|Get the current Colleague SDK environment Settings
Get-ColleagueSession|Get Colleague Session  information
Get-CtxModel|Build the generated generated c# code for a transaction
Get-EntityModel|Build the generated c# code for a entity
Get-SessionTimeout|Return the time when the session will timeout
Initialize-ColleagueService|Initializes this module
Invoke-CTX|Call the Colleage transaction
Open-DmiSession| Open a new session to DMI
Read-TableInfo|Read the information from the Colleague Entity
Read-TableKeys|Read the keys from the Colleague Entity
Set-AppConfig|Sets the Application configuration
Set-AppSettings|Sets or adds information to the AppSettings Section of the App config
Set-ColleagueCreds|Sets the Colleague Credentials in the Application Config
Set-DataContract|Add a new Data Contract for reference in the current session



*Tested:* PowerShell v4.0
