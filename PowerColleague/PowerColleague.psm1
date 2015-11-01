#region ModuleSettings
function Set-AppConfig{
	param(
		[Parameter(Mandatory=$true, Position=1)]
		[string]
		$AppConfigPath
		)
	
  Add-Type -AssemblyName System.Configuration
  [System.AppDomain]::CurrentDomain.SetData("APP_CONFIG_FILE", $AppConfigPath)
}

function Set-ColleagueCreds {
  param(
      [string]
      $username,
      [string]
      $password
  )
  
  Set-AppSettings "colleagueUserName" $username
  Set-AppSettings "colleagueUserPassword" $password
}

function Set-AppSettings {
  param(
    [string]
    $key,
    [string]
    $value
  )
  try
  {
    $configFile = [System.Configuration.ConfigurationManager]::OpenExeConfiguration([System.Configuration.ConfigurationUserLevel]::None)
    $settings = $configFile.AppSettings.Settings
    if($settings[$key]){
    $settings[$key].Value = $value
    }
    else {
    $settings.Add($key, $value)
    }

    $configFile.Save([System.Configuration.ConfigurationSaveMode]::Modified)
    [System.Configuration.ConfigurationManager]::RefreshSection($configFile.AppSettings.SectionInformation.Name)
  }
  catch{
    $_
  }
}

function Initialize-ColleagueService {

  # The Colleague classes need the AppConfig Set

  $defaultVersion = Get-Content "$PSScriptRoot\defaultVersion"

  $defaultPath = "$PSScriptRoot\v$defaultVersion\App.config"
  $AppConfigPath -or ($AppConfigPath =  $defaultPath) > $null
  
  Set-AppConfig $AppConfigPath
  
  $SDKVersion = [System.Configuration.ConfigurationManager]::AppSettings["sdkVersion"]
  
  $EllucianPath = [System.Configuration.ConfigurationManager]::AppSettings["ellucianDependenciesPath"]
  $script:VSExtPath = [System.Configuration.ConfigurationManager]::AppSettings["ellucianVSExtDependenciesPath"]
    
  $script:ColleagueUserName = [System.Configuration.ConfigurationManager]::AppSettings["colleagueUserName"]
  $script:ColleagueUserPassword = [System.Configuration.ConfigurationManager]::AppSettings["colleagueUserPassword"]
  
  Add-Type -Path "$EllucianPath\Ellucian.Colleague.Configuration.dll"
  Add-Type -Path "$EllucianPath\Ellucian.Colleague.Property.dll"
  Add-Type -Path "$EllucianPath\Ellucian.Dmi.Client.dll"
  Add-Type -Path "$EllucianPath\Ellucian.Data.Colleague.dll"
  Add-Type -Path "$EllucianPath\slf4net.dll" # This will give an error if it's not included
  Add-Type -Path "$EllucianPath\Ellucian.WebServices.Core.Config.dll"
  
  ## Load the Microsoft.VisualStudio.Shell that is required for the version
  #Add-Type -Path "$PSScriptRoot\v$SDKVersion\Microsoft.VisualStudio.Shell.dll"
  #Add-Type -Path "$PSScriptRoot\v$SDKVersion\Microsoft.VisualStudio.Shell.Interop.dll"

  Add-Type -Path "$($script:VSExtPath)\Ellucian.WebServices.VS.DataModels.dll"
  Add-Type -Path "$($script:VSExtPath)\Ellucian.WebServices.VS.Ext.dll"
  
  # The below is required for Console based applications
  $newObj = New-Object System.Object
  [Ellucian.Colleague.Configuration.ApplicationServerConfigurationManager]::Instance.Initialize()
  [Ellucian.Colleague.Configuration.ApplicationServerConfigurationManager]::Instance.StoreParameter([Ellucian.Colleague.Property.Properties.Resources]::ValidApplicationServerSettingsFlag, $newObj, [DateTime]::MaxValue)

  # These Types are what is expected to be passed when compiling the Entities in powershell
  $script:TypeAssem = (
    'System, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
    'System.Core, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
    'System.ComponentModel.DataAnnotations, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35',
    'mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
    'System.Runtime.Serialization, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
    "Ellucian.Colleague.Configuration, Version=$SDKVersion.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb",
    "Ellucian.Colleague.Property, Version=$SDKVersion.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb",
    "Ellucian.Data.Colleague, Version=$SDKVersion.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb",
    "Ellucian.Dmi.Client, Version=$SDKVersion.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb",
    "Ellucian.Dmi.Runtime, Version=$SDKVersion.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb"
  )
}
#endregion ModuleSettings

#region SessionInfo

function Get-SessionTimeout {
  $script:timeoutDate
}

function Set-SessionTimeout {
  param ([int] $timeout)
  
  $script:timeoutDate = (Get-Date).AddSeconds($timeout - 5)
}

function Open-DmiSession {        
  $loginReq = New-Object Ellucian.Dmi.Client.StandardLoginRequest
  $login = New-Object Ellucian.Data.Colleague.Repositories.ColleagueLogin
  
  $loginReq.UserID = $script:ColleagueUserName
  $loginReq.Password = $script:ColleagueUserPassword
  
  $session = $login.StandardColleagueLogin($loginReq)
  
  if(!$session.SecurityToken){
    $errs = $session.Errors | % {"Error Code: $($_.ErrorCode)`r`nCategory: $($_.ErrorCategory)`r`nError Message: $($_.ErrorMessageText)" }
    throw $errs -join "`r`n`r`n"
  }
  Set-SessionTimeout $session.TokenTimeout
  $session
}

function Close-DmiSession {
  param(
    [Parameter(Mandatory=$true, Position=1)]
    [Ellucian.Dmi.Client.StandardDmiSession]
    $session
  )

  #$logoutResponse = (New-Object Ellucian.Data.Colleague.Repositories.ColleagueLogin).ColleagueLogout($session)
  (New-Object Ellucian.Data.Colleague.Repositories.ColleagueLogin).ColleagueLogout($session)
}

function Get-ColleagueSession{
  if((Get-Date) -ge (Get-SessionTimeout) ){
      if($script:session){$response = Close-DmiSession $script:session}
      $script:session = Open-DmiSession 
  }
  
  $script:session
}

#endregion SessionInfo

#region ColleagueInfo
function Get-AllApplications{

  if(-not ([System.Management.Automation.PSTypeName]"ColleagueSDK.DataContracts.GetAllApplsRequest").Type){
    $AllAppls = Get-CtxModel UT GET.ALL.APPLS
    Add-Type -ErrorAction SilentlyContinue -ReferencedAssemblies $script:TypeAssem -TypeDefinition $AllAppls -Language CSharp 
  }

  $request = New-Object ColleagueSDK.DataContracts.GetAllApplsRequest
  $typeRequest = $request.getType()
  $typeResponse = (New-Object ColleagueSDK.DataContracts.GetAllApplsResponse).getType()
  $apps = Invoke-CTX $typeRequest $typeResponse $request
  $apps.Applications | % Application
}

function Get-ColleagueEnv {
  [CmdletBinding()]
  param()
  
  $colleagueParams = [System.Web.Configuration.WebConfigurationManager]::GetSection("ColleagueSettings/DmiParameters") -as [Ellucian.WebServices.Core.Config.DmiParameterCustomSection]
  $colleagueEnv = New-Object Ellucian.WebServices.VS.DataModels.ColleagueEnvironment
  
  $session = Get-ColleagueSession
  
  Write-Verbose "Set the ColleagueEnvironment Settings from the Colleague Session and Colleague Settings"
  $colleagueEnv.UserName = $session.WebUserID
  $colleagueEnv.ConnectionName = $colleagueEnv.Account =  $colleagueParams.Environment
  $colleagueEnv.HostAddr = $colleagueParams.Address
  $colleagueEnv.HostPort = $colleagueParams.Port
  $colleagueEnv.SecurityToken = $session.SecurityToken
  $colleagueEnv.ClientControlId = $session.SenderControlId
  
  return $colleagueEnv
}

function Set-DataContract {
  param([string] $dataContractModel, [string] $ClassName)
    if(-not ([System.Management.Automation.PSTypeName]"ColleagueSDK.DataContracts.$ClassName").Type){
    Add-Type -ErrorAction SilentlyContinue -ReferencedAssemblies $script:TypeAssem -TypeDefinition $dataContractModel -Language CSharp 
  }
}
#region ColleagueCTX
function Get-ApplicationCtxs {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [string[]] $applicationNames
  )

  BEGIN { }
  
  PROCESS {
    #$rtnObj = New-Object PSObject
    Write-Verbose "All ApplicationNames $ApplicationNames"
    foreach ($appnme in $ApplicationNames){
      $rtnObj = New-Object PSObject
      $appname = $appnme.ToUpper()
      Add-Member -InputObject $rtnObj -MemberType NoteProperty -Name Application -Value $appname
      $request = New-Object Ellucian.WebServices.VS.DataModels.GetApplCTXRequest
      $request.Application = $appname
      Write-Verbose "Request is $request with $($request.Application)"
     
      $typeRequest = $request.getType()
      $typeResponse = (New-Object Ellucian.WebServices.VS.DataModels.GetApplCTXResponse).getType()
      
      $ctxs = Invoke-CTX $typeRequest $typeResponse $request
      Write-Verbose "Received $ctxs back"
      Add-Member -InputObject $rtnObj -MemberType NoteProperty -Name Transactions -Value $ctxs.Processes
      Write-Output $rtnObj
    }
    #return $rtnObj
  }
  
  END {}
}

function Get-CtxModel {
  param(
    [string] $App,
    [string] $TransactionId
  )
  
 

  $colleagueEnv = Get-ColleagueEnv
  $genDataDetail = New-CtxDetails $App $TransactionId
  $ctxDataModel = New-CtxGeneratorInput $genDataDetail
  
  $ctxDataModel.dataContractNamespace = "ColleagueSDK.DataContracts"
  $ctxDataModel.dateTime = Get-Date
  $ctxDataModel.environment = $colleagueEnv.ConnectionName
  $ctxDataModel.userName = $colleagueEnv.UserName
  
  return New-CtxTransform $ctxDataModel
}

function Invoke-CTX{
  param($typeRequest, $typeResponse, $request)
  $trans = Get-TransactionInvoker
  &"$PSScriptRoot\Invoke-GenericMethod.ps1" $trans -methodName Execute -typeParameters $typeRequest, $typeResponse -methodParameters $request
}

function Get-TransactionInvoker {
  New-Object Ellucian.Data.Colleague.ColleagueTransactionInvoker(Get-ColleagueSession)
}
#endregion ColleagueCTX

#region ColleagueEntities
function Get-DataReader {
  New-Object Ellucian.Data.Colleague.ColleagueDataReader(Get-ColleagueSession)
}

function Read-TableKeys{
  param(
    [Parameter(Mandatory=$true, Position=1)]
    [string]
    $EntityTableName,
    [string]
    $Filter = ""
  )
  $dataReader = Get-DataReader

  $dataReader.Select($EntityTableName.ToUpper(), $Filter)
}

function Get-AppsForEntity {
  param(
    [string] $entity
  )
  $appEntities = Get-AllApplications | Get-ApplicationEntities
  $returnVal = $appEntities | ? {$_.Entities -contains $entity.ToUpper()} | % {$_.Application}
  $returnVal
}

function Read-TableInfo{
  param(
    [Parameter(Mandatory=$true, Position=1)]
    [string]
    $TableName,
    [Parameter(Position=2)]
    [string[]]
    $Fields,
    [Parameter(ParameterSetName="p1", Position=0)]
    [string]
    $Filter = "",
    [Parameter(ParameterSetName="p2", Position=0)]
    [string[]]
    $FilterKeys,
    #[Parameter(ParameterSetName="p3", Position=0)]
    [string]
    $PhysicalFileName,
    [switch]
    $ReplaceTextVMs
  )
  
  $tableCamel = [Ellucian.WebServices.VS.Ext.VSExtUtilities]::ConvertToCamelCase($TableName)
  if(-not ([System.Management.Automation.PSTypeName]"ColleagueSDK.DataContracts.$tableCamel").Type){
    $app = Get-AppsForEntity $TableName
    $app = if($App -and ($App.Count -gt 1)) {$App[0]} else{$App}
    $testsource = if($Fields){
      Get-EntityModel $app $TableName.ToUpper() -FieldNames $Fields
    }
    else {
      Get-EntityModel $app $TableName.ToUpper() -GetDetail 
    }
    
    Add-Type -ErrorAction Stop -ReferencedAssemblies $script:TypeAssem -TypeDefinition $testSource -Language CSharp 
  }
  $dataReader = Get-DataReader

  $invalidRecords = New-Object 'System.Collections.Generic.Dictionary[string,string]'

  $type = (New-Object "ColleagueSDK.DataContracts.$TableCamel").getType()
  switch ($PSCmdlet.ParameterSetName)
  {
    "p2" {
      $params = @()
      if($PhysicalFileName) { $params += $PhysicalFileName}
      $params +=  @($FilterKeys, [bool]$ReplaceTextVMs)
      &"$PSScriptRoot\Invoke-GenericMethod.ps1" $dataReader -methodName "BulkReadRecord" -typeParameters $type -methodParameters $params
    }

    #"p3" {
    #}

    default {
      $params = @()
      if($PhysicalFileName) { $params += $PhysicalFileName}
      $params +=  @($Filter, [bool]$ReplaceTextVMs)
      &"$PSScriptRoot\Invoke-GenericMethod.ps1" $dataReader -methodName "BulkReadRecord" -typeParameters $type -methodParameters $params
    }
  }


}

function Get-ApplicationEntities {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [string[]] $applicationNames
  )

  BEGIN {
    if(-not ([System.Management.Automation.PSTypeName]"ColleagueSDK.DataContracts.GetApplEntitiesRequest").Type){
      $AllEntities= Get-CtxModel UT GET.APPL.ENTITIES
      Add-Type -ErrorAction SilentlyContinue -ReferencedAssemblies $script:TypeAssem -TypeDefinition $AllEntities -Language CSharp 
    }
  }
  
  PROCESS {
    #$rtnObj = New-Object PSObject
    foreach ($appnme in $ApplicationNames){
      $rtnObj = New-Object PSObject
      $appname = $appnme.ToUpper()
      Add-Member -InputObject $rtnObj -MemberType NoteProperty -Name Application -Value $appname
      $request = New-Object ColleagueSDK.DataContracts.GetApplEntitiesRequest
      $request.TvApplication = $appname
     
      $typeRequest = $request.getType()
      $typeResponse = (New-Object ColleagueSDK.DataContracts.GetApplEntitiesResponse).getType()
      
      $entities = Invoke-CTX $typeRequest $typeResponse $request
      Add-Member -InputObject $rtnObj -MemberType NoteProperty -Name Entities -Value $entities.TvEntities
      Write-Output $rtnObj
    }
    #return $rtnObj
  }
  
  END {}
}

function Get-EntityModel {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, Position=1)]
    [string] $App,
    [Parameter(Mandatory=$true, Position=2)]
    [string] $FileName,
    [Parameter(ParameterSetName="p1", Position=0)]
    [string[]] $FieldNames,
    [Parameter(ParameterSetName="p2", Position=0)]
    [switch] $GetDetail
  )

switch ($PSCmdlet.ParameterSetName)
  {
    "p2" { $fileDetails = New-FileDetails $App.ToUpper() $FileName.ToUpper() -DetailMode }
    default{$fileDetails = New-FileDetails $App.ToUpper() $FileName.ToUpper() -FieldNames $FieldNames}
  }
  Write-Verbose "Create Entity Generator from New-EntityGeneratorInput"
  $entityDataModelGenerator = New-EntityGeneratorInput $fileDetails 
  
  $entityDataModelGenerator.dataContractNamespace = "ColleagueSDK.DataContracts"
  $entityDataModelGenerator.dateTime = Get-Date

  Write-Verbose "Transform the generator to C# code and return"
  return New-EntityTransform $entityDataModelGenerator
}
#endregion ColleagueEntities

#endregion ColleagueInfo

#region VSExtUtilitiesRebuild
function New-EntityGeneratorInput {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [Ellucian.WebServices.VS.DataModels.ColleagueFileDetails]
    $FileDetails
  )
  Write-Verbose "Create the Entity Models and add to Powershell"
  $code = @"
using System;
using System.Collections.Generic;
using System.Xml.Serialization;
namespace Ellucian.WebServices.VS.Contract.Generator.Entity
{
  public class EntityAssociationMemberTag
  {
    [XmlAttribute]
    public string name;
    [XmlAttribute]
    public bool isController;
    [XmlAttribute]
    public string dataType;
  }
  
  public class EntityAssociationMembersTag
  {
    [XmlElement]
    public List<EntityAssociationMemberTag> entityAssociationMember;
    public EntityAssociationMembersTag()
    {
      this.entityAssociationMember = new List<EntityAssociationMemberTag>();
    }
  }
    
  public class EntityDataElementTag
  {
    [XmlAttribute]
    public string name;
    [XmlAttribute]
    public string legacyName;
    [XmlAttribute]
    public string dataType;
    [XmlAttribute]
    public string displayFormat;
    [XmlAttribute]
    public bool isInquiryOnly;
    [XmlAttribute]
    public bool isRequired;
    [XmlAttribute]
    public string comment;
    [XmlAttribute]
    public bool isList;
    [XmlAttribute]
    public bool isAssociated;
    [XmlAttribute]
    public string orderNumber;
  }
    
  public class EntityAssociationTag
  {
    [XmlAttribute]
    public string name;
    [XmlAttribute]
    public string origName;
    [XmlElement]
    public EntityAssociationMembersTag entityAssociationMembers;
  }
    
  public class EntityContentsTag
  {
    [XmlElement]
    public List<EntityDataElementTag> entityDataElement;
    [XmlElement]
    public List<EntityAssociationTag> entityAssociation;
    public EntityContentsTag()
    {
      this.entityDataElement = new List<EntityDataElementTag>();
      this.entityAssociation = new List<EntityAssociationTag>();
    }
  }
    
  public class LegacyFileTag
  {
    [XmlAttribute]
    public string name;
    [XmlAttribute]
    public string implementedInterface;
    [XmlAttribute]
    public string type;
    [XmlAttribute]
    public string application;
    [XmlAttribute]
    public string colleagueId;
    [XmlAttribute]
    public bool isInquiryOnly;
    [XmlElement]
    public EntityContentsTag contents;
  }


  public class Entities
  {
    [XmlElement]
    public LegacyFileTag legacyFile;
  }
    
  [XmlRoot("hostEntitySet", Namespace = "http://schemas.microsoft.com/dsltools/AppServerTransactionBuilder")]
  public class EntityDataModelGeneratorXml
  {
    [XmlAttribute]
    public string dslVersion;
    [XmlAttribute]
    public string Id;
    [XmlAttribute]
    public string application;
    [XmlAttribute]
    public string environment;
    [XmlAttribute]
    public string transactionType;
    [XmlAttribute]
    public string dataContractNamespace;
    [XmlAttribute]
    public string dataContractVersion;
    [XmlElement]
    public Entities entities;
    [XmlAttribute]
    public string dateTime;
    [XmlAttribute]
    public string url;
    [XmlAttribute]
    public string userName;
  }
}
"@
  
  $TypesAssemsCustom = $script:TypeAssem + "System.Xml, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089"
  Add-Type -ReferencedAssemblies $TypesAssemsCustom -TypeDefinition $code -Language CSharp
  
  $entityDataModelGeneratorXml = New-Object Ellucian.WebServices.VS.Contract.Generator.Entity.EntityDataModelGeneratorXml
  
  Write-Verbose "Set the entity values the same as from the VS ext"
  $entityDataModelGeneratorXml.Id = "c6c965be-fde7-4640-8425-e01f4fd89682" # no idea what this is, just copied it from the extension
  $entityDataModelGeneratorXml.application = $fileDetails.Application
  $entityDataModelGeneratorXml.dataContractVersion = "1.0"
  $entityDataModelGeneratorXml.environment = $fileDetails.SourceEnvironment

  $entities = New-Object Ellucian.WebServices.VS.Contract.Generator.Entity.Entities
  $legacyFileTag = New-Object Ellucian.WebServices.VS.Contract.Generator.Entity.LegacyFileTag

  $legacyFileTag.name = $fileDetails.FileNameCamelCase
  $legacyFileTag.implementedInterface = "IColleagueEntity"
  $legacyFileTag.colleagueId = $fileDetails.FileName
  $legacyFileTag.isInquiryOnly = $true
  $legacyFileTag.type = $fileDetails.FileType
  $entities.legacyFile = $legacyFileTag
  $entityDataModelGeneratorXml.entities = $entities

  $entityContentsTag = New-Object Ellucian.WebServices.VS.Contract.Generator.Entity.EntityContentsTag

  try{
    foreach($current in $fileDetails.Fields)
    {
      Write-Verbose "Processing field: $current"
      if($current.RecordKey -eq "GUID Information"){
        $legacyFileTag.implementedInterface= "IColleagueGuidEntity"
      }
      elseif ($current.Source){
        $entityDataElementTag = New-Object Ellucian.WebServices.VS.Contract.Generator.Entity.EntityDataElementTag

        $entityDataElementTag.name = [Ellucian.WebServices.VS.Ext.VSExtUtilities]::ConvertToCamelCase($current.Recordkey)
        $entityDataElementTag.isList = $current.DatabaseUsageType -in @("L", "Q")
        $entityDataElementTag.isAssociated = $current.DatabaseUsageType -eq "A"
        $entityDataElementTag.dataType = [Ellucian.WebServices.VS.Ext.VSExtUtilities]::GetElementDataType($current)
        $entityDataElementTag.legacyName = if ($legacyFileTag.type -eq "LOGI") { $current.PhysicalCddName } else { $current.Recordkey }
        $entityDataElementTag.displayFormat = [Ellucian.WebServices.VS.Ext.VSExtUtilities]::GetDataDisplayFormatFromConvCode($entityDataElementTag.dataType, $current.InformConversionString)
        [int] $num = 0
        if(![Int32]::TryParse($current.FieldPlacement, [ref] $num)){
            throw New-Object Ellucian.WebServices.VS.Ext.VSExtDataException("Invalid field placement for CDD element $current.Recordkey")
        }
        $entityDataElementTag.orderNumber = ($num - 1).ToString();
        [string] $text = $current.Recordkey;
        if ($entityDataElementTag.dataType -eq "long?")
        {
          [int] $num2 = 0;
          if (![Int32]::TryParse($current.MaximumStorageSize, [ref] $num2))
          {
            [Int32]::TryParse($current.DefaultDisplaySize, [ref] $num2)
          }
          if ($num2 -ge 19)
          {
            $text += ";This transaction variable has a conversion type of `"MD0`", and its size exceeds the limit of 18 digits for .Net";
          }
        }
        $entityDataElementTag.comment = $text;
        $entityContentsTag.entityDataElement.Add($entityDataElementTag);
      }
    }
    
    foreach($current2 in  $fileDetails.Associations.Values){
      Write-Verbose "Proccessing association: $current2"
      if ($current2.AssocName)
      {
        $entityAssociationTag = New-Object Ellucian.WebServices.VS.Contract.Generator.Entity.EntityAssociationTag

        $entityAssociationTag.origName = $current2.AssocName;
        $entityAssociationTag.name = [Ellucian.WebServices.VS.Ext.VSExtUtilities]::ConvertToCamelCase($current2.AssocName)
        $entityAssociationTag.entityAssociationMembers = New-Object Ellucian.WebServices.VS.Contract.Generator.Entity.EntityAssociationMembersTag

        foreach ($current3 in $current2.AssocMembers)
        {
          Write-Verbose "Processing member: $current3 in association: $current2"
          $entityAssociationMemberTag = New-Object Ellucian.WebServices.VS.Contract.Generator.Entity.EntityAssociationMemberTag

          $entityAssociationMemberTag.name = [Ellucian.WebServices.VS.Ext.VSExtUtilities]::ConvertToCamelCase($current3.AssocMemberName)
          $entityAssociationMemberTag.isController = $current3.IsController
          $entityAssociationMemberTag.dataType = $current3.DataType
          $entityAssociationTag.entityAssociationMembers.entityAssociationMember.Add($entityAssociationMemberTag)
        }
        $entityContentsTag.entityAssociation.Add($entityAssociationTag)
      }
    }
  }
  catch{
    throw New-Object Ellucian.WebServices.VS.Ext.VSExtException("Error occurred during XML doc generation: $_")
  }
  $entityDataModelGeneratorXml.entities.legacyFile.contents = $entityContentsTag
  return $entityDataModelGeneratorXml
}

function New-FileDetails {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, Position=1)]
    [string] $App,
    [Parameter(Position=2)]
    [string] $FileName,
    [Parameter(ParameterSetName="p1", Position=0)]
    [string[]] $FieldNames,
    [Parameter(ParameterSetName="p2", Position=0)]
    [switch] $DetailMode,
    
    [Parameter(ParameterSetName="p3", Position=0)]
    [string[]] $FileNames
  )


  Write-Verbose "Add Assembly System.Web, System.XML"
  Add-Type -AssemblyName System.Web
  Add-Type -AssemblyName System.Xml
  
  Write-Verbose "Get the Colleague Settings from the AppConfig"
  
  $colleagueEnv = Get-ColleagueEnv
  
  if(!$FieldNames){$FieldNames = New-Object Collections.Generic.List[String]}
  
  $returnVal = @()
  switch ($PSCmdlet.ParameterSetName)
  {
    "p3" {
        foreach($FileName in $FileNames)
        {
          $filename = $filename.ToUpper() -replace "APPL", "appl" 
          $returnVal += [Ellucian.WebServices.VS.Ext.VSExtUtilities]::BuildFileDetails($colleagueEnv, $app, $filename, $filename, ([Collections.Generic.List[String]]$FieldNames), $true)
        }
    }
    default {
      $filename = $filename.ToUpper() -replace "APPL", "appl" 
      $returnVal = [Ellucian.WebServices.VS.Ext.VSExtUtilities]::BuildFileDetails($colleagueEnv, $app, $filename, $filename, ([Collections.Generic.List[String]]$FieldNames), [bool]$DetailMode)
    }
  }
  return $returnVal
}

function New-EntityTransform {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [Ellucian.WebServices.VS.Contract.Generator.Entity.EntityDataModelGeneratorXml]
    $fileModel
  )
  BEGIN {}
  
  PROCESS {
      Write-Verbose "Creating C# template from $fileModel"
      $fileModel.Entities.LegacyFile.name = [Ellucian.WebServices.VS.Ext.VSExtUtilities]::ConvertToCamelCase($fileModel.Entities.LegacyFile.name)
      
      Write-Verbose "Head of template contains Recordkey and _AppServerVersion"
      $modeltemplate = @"
//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated by the "(DSL/T4 Generator - Version 1.1)" 
//      Copy-Cat Generator in PowerShell by Roger Garrison
//     Last generated on $($fileModel.dateTime) by user $($fileModel.userName)
//
//     Type: ENTITY
//     Entity: $($fileModel.Entities.LegacyFile.colleagueId)
//     Application: $($fileModel.application)
//     Environment: $($fileModel.environment)
//
//     Changes to this file may cause incorrect behavior and will be lost if
//     the code is regenerated.
// </auto-generated>
//------------------------------------------------------------------------------

using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Web;
using System.Runtime.Serialization;
using System.CodeDom.Compiler;
using Ellucian.Dmi.Runtime;
using Ellucian.Data.Colleague;

namespace $($fileModel.dataContractNamespace) 
{
  [GeneratedCodeAttribute("Colleague Data Contract Generator", "1.1")]
  [DataContract(Name = "$($fileModel.Entities.LegacyFile.name)")]
  [ColleagueDataContract(GeneratedDateTime = "$($fileModel.dateTime)", User = "$($fileModel.userName)")]
  [EntityDataContract(EntityName = "$($fileModel.Entities.LegacyFile.colleagueId)", EntityType = "$($fileModel.Entities.LegacyFile.type)")]
  public partial class $($fileModel.Entities.LegacyFile.name) : $($fileModel.Entities.LegacyFile.implementedInterface)
  {
    /// <summary>
    /// Version
    /// </summary>
    [DataMember]
    public int _AppServerVersion { get; set; }

    /// <summary>
    /// Record Key
    /// </summary>
    [DataMember]
    public string Recordkey { get; set; }

    public void setKey(string key)
    {
      Recordkey = key;
    }

"@
      
      [int] $elementCount = 0
      if ($fileModel.Entities.LegacyFile.impementedInterface -eq "IColleagueGuidEntity") {
        Write-Verbose "If $fileModel implements the IColleagueGuidEntity Interface, add the Record Guid and Record Model Name"
        $modeltemplate += @"

    /// <summary>
    /// Record GUID
    /// </summary>
    [DataMember(Name = "RecordGuid")]
    public string RecordGuid { get; set; }

    /// <summary>
    /// Record Model Name
    /// </summary>
    [DataMember(Name = "RecordModelName")]
    public string RecordModelName { get; set; }
"@
      }

      [int] $elementCount = 0
      foreach($element in $fileModel.Entities.LegacyFile.Contents.EntityDataElement)
      {
        Write-Verbose "Add element ($element) to the C# output file"
        $modeltemplate += @"

    /// <summary>
    /// CDD Name: $($element.comment)
    /// </summary>
    [DataMember(Order = $($element.orderNumber), Name = "$($element.legacyName)")]
"@
        
        if($element.dataType -notin @("string", "int", "int?", "long", "long?")){ # convert if the format is not one of the primitive types
          $modeltemplate += @"

    [DisplayFormat(DataFormatString = "$($element.displayFormat)")]
    [ColleagueDataMember(UseEnvisionInternalFormat = true)]
"@
        }

        if ($element.isList -or $element.isAssociated) {
          $modeltemplate += @"

    public List<$($element.DataType)> $($element.Name) { get; set; }

"@
        }
        else {
          $modeltemplate += @"

    public $($element.DataType) $($element.Name) { get; set; }

"@
        }

        $elementCount += 1
      }

      foreach($assoc in $fileModel.Entities.LegacyFile.Contents.EntityAssociation)
      {
        $modeltemplate += @"

    /// <summary>
    /// Entity association member
    /// </summary>
    [DataMember]
    public List<$($fileModel.entities.legacyFile.name)$($assoc.name)> $($assoc.name)EntityAssociation { get; set; }

"@
        
        $elementCount += 1
      }

      if($fileModel.Type -eq "BLOB" -and $elementCount -eq 0)
      {
        $modeltemplate += @"

    [DataMember(Order = 0)]
    public List<string> FieldCollection { get; set; }

"@
      }
      
      $modeltemplate += @"
  
    // build up all the Associated objects and add them to the properties
    public void buildAssociations()
    {
"@
      
      foreach($assoc in $fileModel.Entities.LegacyFile.Contents.EntityAssociation)
      {
        $modeltemplate += @"

      // EntityAssociation Name: $($assoc.OrigName)

      $($assoc.Name)EntityAssociation = new List<$($fileModel.entities.legacyFile.name)$($assoc.name)>();
"@
        
        $controllerName = ($assoc.EntityAssociationMembers.EntityAssociationMember | Where IsController).Name
        if(!$controllerName){ $controllerName = $assoc.EntityassociationMembers.EntityAssociationMember[0].Name}

        $modeltemplate += @"

      if($controllerName != null)
      {
        int num$($assoc.Name) = $controllerName.Count;
        for(int i = 0; i < num$($assoc.Name); i++)
        {
"@
        $valIndex = 0
        foreach($ascMember2 in $assoc.EntityAssociationMembers.EntityAssociationMember)
        {
          $initVal = '""'

          if($ascMember2.dataType -notmatch "string"){
            $initVal = "null"
          }

          if($ascMember2.Name -match $controllerName) {
            $modeltemplate += @"

          $($ascMember2.DataType) value$valIndex = $initVal;
          value$valIndex = $($ascMember2.Name)[i];
"@
          }
          else {
            $modeltemplate += @"

          $($ascMember2.DataType) value$valIndex = $initVal;
          if($($ascMember2.Name) != null && i < $($ascMember2.Name).Count)
          {
            value$valIndex = $($ascMember2.Name)[i];
          }
"@
          }

          $valIndex += 1
        }

        $modeltemplate += @"

          $($assoc.Name)EntityAssociation.Add(new $($fileModel.entities.legacyFile.name)$($assoc.name)(
"@
        $counter = 0
        foreach($ascMember2 in $assoc.EntityAssociationMembers.EntityAssociationMember)
        {
          $modeltemplate += "value$counter"
          $counter += 1
          if($counter -ne $assoc.EntityAssociationMembers.EntityAssociationMember.Count){ $modeltemplate += ","}
        }
        $modeltemplate += "));`r`n`r`n        }`r`n      }"
      }

      $modeltemplate += @"
  
    }
  }
"@
        
      foreach($assoc in $fileModel.Entities.LegacyFile.Contents.EntityAssociation)
      {
        $modeltemplate += @"


  // EntityAssociation classes
    
  [Serializable]
  public partial class $($fileModel.entities.legacyFile.name)$($assoc.name)
  {
"@
       
        foreach($ascMember3 in $assoc.EntityAssociationMembers.EntityAssociationMember)
        {
          $modeltemplate += @"

    public $($ascMember3.DataType) $($ascMember3.Name)AssocMember;
"@
        }
        
        $modeltemplate += @"

    public $($fileModel.entities.legacyFile.name)$($assoc.name) () {}
    public $($fileModel.entities.legacyFile.name)$($assoc.name) (
"@
        $counter = 0
        foreach($ascMember4 in $assoc.EntityAssociationMembers.EntityAssociationMember)
        {
          $modeltemplate += "`r`n      $($ascMember4.DataType) in$($ascMember4.name)"
          $counter += 1
          if($counter -ne $assoc.EntityAssociationMembers.EntityAssociationMember.Count){ $modeltemplate += ","}
        }
        $modeltemplate += ")`r`n    {"

        foreach($ascMember5 in $assoc.EntityAssociationMembers.EntityAssociationMember)
        {
          $modeltemplate += "`r`n      $($ascMember5.Name)AssocMember = in$($ascMember5.Name);"
        }

        $modeltemplate +=@"
    
    }
  }
"@
      }
        $modeltemplate +=@"

}
"@
      return $modeltemplate
  }
  
  END {}
}
  
  
function New-CtxTransform {
  [CmdletBinding()]
  param(
    $ctxModel
  )

  #region NestedFunctions
  function Assert-IsInbound {
    param( [string] $test)
    $test -in @("IN", "INOUT")
  }

  function Assert-IsOutbound {
    param( [string] $test)
    $test -in @("OUT", "INOUT")
  }

  function Get-DatatelBooleanAttribute {
    param( 
      [string] $type,
      [switch] $leadingComma
    )

    $retVal = [string]::Empty

    if($leadingComma){ $retVal += "," }

    $retVal = switch ($type) {
      "BooleanYN" { "$retVal UseEnvisionBooleanConventions = EnvisionBooleanTypesEnum.YesNo" }
      "Boolean10" { "$retVal UseEnvisionBooleanConventions = EnvisionBooleanTypesEnum.OneZero" }
      default { [String]::Empty }
    }

    $retVal
  }
  
  function ConvertTo-ClrType {
    param ([string] $type)

    switch -regex ($type) {
        "^(?:(?:Multiline)?Text|\s*)$" { "string" } # add empty to map to string, because I think it fits better
        #"BooleanYN" { "bool" }
        #"Boolean10" { "bool10" }
        "Boolean" { "bool" }
        "Uri" { "uri" }
        "Date|Time" { "DateTime" }
        "Integer" { "int" }
        "Double|Decimal|Long|Float" { $_.ToLower() }
        "RealNumber" { "single" }
        default { "object" }
    }
  }
  #endregion NestedFunctions

  $tx = $ctxModel.Transactions.legacyProcess[0]
  $modelTemplate = @"
//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated by the "(DSL/T4 Generator - Version 1.1)" 
//      Copy-Cat Generator in PowerShell by Roger Garrison
//     Last generated on $($ctxModel.dateTime) by user $($ctxModel.userName)
//
//     Type: CTX
//     Transaction ID: $($tx.ColleagueId)
//     Application: $($ctxModel.application)
//     Environment: $($ctxModel.environment)
//
//     Changes to this file may cause incorrect behavior and will be lost if
//     the code is regenerated.
// </auto-generated>
//------------------------------------------------------------------------------

using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Web;
using System.Runtime.Serialization;
using System.CodeDom.Compiler;
using Ellucian.Dmi.Runtime;
using Ellucian.Data.Colleague;

namespace $($ctxModel.dataContractNamespace) 
{

"@
  
  # Go through each group of elements
  $firstGroup = $true
  foreach($grp in $ctxModel.Groups.Group)
  {
    # Only include group if at least one element is inbound or outbound
    $isGroupOutbound = $isGroupInbound = $false
    foreach($mbr in $grp.GroupMembers.GroupMember)
    {
      $isGroupInbound = Assert-IsInbound $mbr.direction
      $isGroupOutbound = Assert-IsOutbound $mbr.direction
    }

    # Only include group if it's inbound and/or outbound
    if( $isGroupInbound -or $isGroupOutbound) {
      if( -not $firstGroup) # i'm not sure why this is an empty if ... keep it for now
      {
      }

      $firstGroup = $false

      $modelTemplate += @"
  [DataContract]
  public partial class $($grp.Name)
  {

"@
      $firstGroupMember =  $isController = $true
      foreach($mbr in $grp.GroupMembers.GroupMember)
      {
        # Only include members if it's inbound and/or outbound
        $elementIsInbound = Assert-IsInbound $mbr.direction
        $elementIsOutbound =  Assert-IsOutbound $mbr.direction
 
        # Controller is foreced inbound/outbound if any elments are
        if ($isController) {
          if ($isGroupInbound){ $elementIsInbound = $true }
          if ($isGroupOutbound){ $elementIsOutbound = $true }
        }

        if ($elementIsInBound -or $elementIsOutbound) {
          if (-not $firstGroupMember) { # again, I'm not sure why this is empty ... keep it for now
          }

          $firstGroupMember = $false
          # Start with optional comment

          if ($mbr.Comment) {
            $modelTemplate += @"
    /// <summary>
    /// $($mbr.Comment)
    /// </summary>
"@
          }

          if ($mbr.isRequired) {
            $modelTemplate += "    [DataMember(IsRequired = true)]`r`n"
          }
          else {
            $modelTemplate += "    [DataMember]`r`n"
          }

          if ($mbr.displayFormat) {
            $modelTemplate += "    [DisplayFormat(DataFormatString = `"$($mbr.displayFormat)`")]`r`n"
          }

          $sctrqParameters = [String]::Empty
          # if member is inbound, flag it as such
          if ($elementIsInbound) {
            $sctrqParameters += ", InBoundData = true"
          }

          # if member is outbound, flag it as such
          if ($elementIsOutbound) {
            $sctrqParameters += ", OutBoundData = true"
          }

          $datatelBooleanAttr = Get-DatatelBooleanAttribute $mbr.dataType -LeadingComma
          $modelTemplate += "    [SctrqDataMember(AppServerName = `"$($mbr.LegacyName)`"$datatelBooleanAttr$sctrqParameters)]`r`n"

          $clrType = ConvertTo-ClrType $mbr.dataType
          
          if ($clrType -match "string|bool" ) {
            $modelTemplate += "    public $clrType $($mbr.Name) { get; set; }`r`n`r`n"
          }
          elseif ($clrType -match "uri") {
            $modelTemplate += "    public Uri $($mbr.Name) { get; set; }`r`n`r`n"
          }
          else {
            $modelTemplate += "    public Nullable<$clrType> $($mbr.Name) { get; set; }`r`n`r`n"
          }

          $isController = $false
        }
      }
      $modelTemplate += "  }`r`n"
    }
  }

  $firstDataContract = $firstGroup
  foreach( $i in 0..1)
  {
    $initStmts = @()

    $isGlobalInbound = $false
    $isGlobalOutbound = $false

    $globalPrefix = [String]::Empty

    switch ($i) {
      0 {
          $isGlobalInbound = $true
          $isGlobalOutbound = $false
          $globalPrefix = "Request"
        }
      1 {
          $isGlobalInbound = $false
          $isGlobalOutbound = $true
          $globalPrefix = "Response"
        }
      default { throw  "Too many values"}
    }

    if ( -not $firstDataContract){# again, I'm not sure why this is empty ... keep it for now
    }

    $anonymous = [String]::Empty

    if($tx.isAnonymous) { $anonymous += ", PublicTransaction = true"}

    $modelTemplate += @"
    
  [GeneratedCodeAttribute("Colleague Data Contract Generator", "1.1")]
  [DataContract]
  [ColleagueDataContract(ColleagueId = "$($tx.colleagueId)", GeneratedDateTime = "$($ctxModel.dateTime)", User = "$($ctxModel.userName)")]
  [SctrqDataContract(Application = "$($ctxModel.Application)", DataContractVersion = $($ctxModel.DataContractVersion)$anonymous)]
  public partial class $($tx.Name)$globalPrefix
  {
    /// <summary>
    /// Version
    /// </summary>
    [DataMember]
    public int _AppServerVersion { get; set; }


"@
    $firstContent = $true
    foreach($fld in $tx.contents.dataElement)
    {
      if (( (Assert-IsInbound $fld.Direction) -and $isGlobalInbound) -or ( (Assert-IsOutbound $fld.Direction) -and $isGlobalOutbound)){
        if ( -not $firstContent) { #this is getting annoying, why are all of these empty?
        }

        $firstContent = $false

        # Start with optional comment
        if ($fld.comment){
          $modelTemplate += @"
    /// <summary>
    /// $($fld.comment)
    /// </summary>
"@
        }

        # if data element is required, flag it
        if ($fld.isRequired) {
          $modelTemplate += "    [DataMember(IsRequired = true)]`r`n"
        }
        else
        {
          $modelTemplate += "    [DataMember]`r`n"
        }

        if ($fld.displayFormat) {
          $modelTemplate += "    [DisplayFormat(DataFormatString = `"$($fld.displayFormat)`")]`r`n"
        }

        $sctrqParameters = [String]::Empty
        # if data element is inbound, flag it
        if ((Assert-IsInbound $fld.direction) -and $isGlobalInbound){ 
          $sctrqParameters += ", InBoundData = true"
        }

        # if data element is outbound, flag it
        if ((Assert-IsOutbound $fld.direction) -and $isGlobalOutbound){ 
          $sctrqParameters += ", OutBoundData = true"
        }

        $modelTemplate += "    [SctrqDataMember(AppServerName = `"$($fld.legacyName)`"$(Get-DatatelBooleanAttribute $fld.DataType -LeadingComma)$sctrqParameters)]`r`n"

        $clrType = ConvertTo-ClrType $fld.DataType
        if ($clrType -match "string") {
          # Only CDD Elements can be of type list, and lists cannot be in groups
          if ($fld.isList) {
            $modelTemplate += "    public List<string> $($fld.Name) { get; set; }`r`n`r`n"
            $initStmts += "$($fld.Name) = new List<string>();"
          }
          else {
            $modelTemplate += "    public string $($fld.Name) { get; set; }`r`n`r`n"
          }
        }
        elseif ($clrType -match "bool") {
          if ($fld.isList) {
            $modelTemplate += "    public List<bool> $($fld.Name) { get; set; }`r`n`r`n"
            $initStmts += "$($fld.Name) = new List<bool>();"
          }
          else {
            $modelTemplate += "    public bool $($fld.Name) { get; set; }`r`n`r`n"
          }
        }
        elseif ($clrType -match "uri") {
          if ($fld.isList) {
            $modelTemplate += "    public List<Uri> $($fld.Name) { get; set; }`r`n`r`n"
            $initStmts += "$($fld.Name) = new List<Uri>();"
          }
          else {
            $modelTemplate += "    public Uri $($fld.Name) { get; set; }`r`n`r`n"
          }
        }
        else{
          if ($fld.isList) {
            $modelTemplate += "    public List<Nullable<$($clrType)>> $($fld.Name) { get; set; }`r`n`r`n"
            $initStmts += "$($fld.Name) = new List<Nullable<$($clrType)>>();"
          }
          else {
            $modelTemplate += "    public Nullable<$($clrType)> $($fld.Name) { get; set; }`r`n`r`n"
          }
        }
      }
    }

    foreach($grpref in $tx.contents.groupReference)
    {
      $grp = $ctxModel.groups.Group | ? {$_.name -eq $grpref.name}
      # only include group if at least one element is inbound our outbound or required

      $isGroupRequired = $isGroupOutbound = $isGroupInbound = $false
      foreach($mbr in $grp.GroupMembers.GroupMember)
      {
        $isGroupInbound = $isGroupInbound -or (Assert-IsInbound $mbr.Direction)
        $isGroupOutBound = $isGroupOutBound -or (Assert-IsOutbound $mbr.direction)

        $isGroupRequired = $isGroupRequired -or $mbr.isRequired
      }

      # Only include group if it is inbound and/or outbound 
      if (($isGroupInbound -and $isGlobalInbound) -or ($isGroupOutbound -and $isGlobalOutbound)){
        if ( -not $firstContent) { # again! 
        }
        $firstContent = $false
        # if group is required, flag it
        if ($isGroupRequired){
          $modelTemplate += "    [DataMember(IsRequired = true)]`r`n"
        }
        else {
          $modelTemplate += "    [DataMember]`r`n"
        }
        $sctrqParameters = [string]::Empty

        if ($isGroupInbound -and $isGlobalInbound){
          $sctrqParameters += ", InBoundData = true"
        }

        if ($isGroupOutbound -and $isGlobalOutbound){
          $sctrqParameters += ", OutBoundData = true"
        }

        $modelTemplate += @"
    [SctrqDataMember(AppServerName = "$($grpref.legacyName)"$(Get-DatatelBooleanAttribute $grpref.dataType -LeadingComma)$sctrqParameters)]
    public List<$($grp.Name)> $($grpref.Name) { get; set; }


"@
        $initStmts += "$($grpref.Name) = new List<$($grp.Name)>();"
      }
    }
    
    # Constructor that initializes all list<>-type auto properties in this class
    $modelTemplate += @"
    public $($tx.Name + $globalPrefix)()
    {
      $($initStmts -join "`r`n      ")
    }
  }

"@
  }
  $modelTemplate += "}`r`n"
  return $modelTemplate
}

function New-CtxDetails {
  param(
    [string] $Application,
    [string[]] $TransactionId
  )
  $request = New-Object Ellucian.WebServices.VS.DataModels.GetCtxDetailsRequest
  
  $request.PrcsId = $TransactionId.ToUpper()
  $request.Application = $Application.ToUpper()
  
  $resp = New-Object Ellucian.WebServices.VS.DataModels.GetCtxDetailsResponse
  Invoke-CTX $request.GetType() $resp.GetType() $request
}

function New-CtxGeneratorInput {
  param(
    $ctxDetails
  )
  [Ellucian.WebServices.VS.Ext.VSExtUtilities]::CreateCtxGeneratorInput($ctxDetails, $ctxDetails.PrcsAliasName)
}
#endregion VSExtUtilitiesrebuild

Initialize-ColleagueService
