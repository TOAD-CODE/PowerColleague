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
    
    AddUpdateAppSettings "colleagueUserName" $username
    AddUpdateAppSettings "colleagueUserPassword" $password
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

function Initialize-ColleagueService{

    # The Colleague classes need the AppConfig Set

    $defaultPath = "$PSScriptRoot\App.config"
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
    
    # The below is required for Console based applications
    $newObj = New-Object System.Object
    [Ellucian.Colleague.Configuration.ApplicationServerConfigurationManager]::Instance.Initialize()
    [Ellucian.Colleague.Configuration.ApplicationServerConfigurationManager]::Instance.StoreParameter([Ellucian.Colleague.Property.Properties.Resources]::ValidApplicationServerSettingsFlag, $newObj, [DateTime]::MaxValue )

    # These Types are what is expected to be passed when compiling the Entities in powershell
    $script:TypeAssem = (
      'System, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
      'System.Core, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
      'System.ComponentModel.DataAnnotations, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35',
      'mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
      'System.Runtime.Serialization, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
      'Ellucian.Colleague.Configuration, Version=1.6.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb',
      'Ellucian.Colleague.Property, Version=1.6.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb',
      'Ellucian.Data.Colleague, Version=1.6.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb',
      'Ellucian.Dmi.Client, Version=1.6.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb',
      'Ellucian.Dmi.Runtime, Version=1.6.0.0, Culture=neutral, PublicKeyToken=55c547a3498c89fb'
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
        throw [System.ArgumentNullException] $session.Errors
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

function Get-DataReader {
  New-Object Ellucian.Data.Colleague.ColleagueDataReader(Get-ColleagueSession)
}

function Get-TransactionInvoker {
  New-Object Ellucian.Data.Colleague.ColleagueTransactionInvoker(Get-ColleagueSession)
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
    [Parameter(ParameterSetName="p1", Position=0)]
    [string]
    $Filter = "",
    [Parameter(ParameterSetName="p2", Position=0)]
    [string[]]
    $FilterKeys,
    #[Parameter(ParameterSetName="p3", Position=0)]
    #[string]
    #$PhysicalFileName,
    [switch]
    $ReplaceTextVMs
  )
  
  if(-not ([System.Management.Automation.PSTypeName]"ColleagueSDK.DataContracts.$TableName").Type){
    $app = Get-AppsForEntity $TableName
    $testsource = Get-EntityModel $app $TableName.ToUpper() -GetDetail #-FieldNames FIRST.NAME, LAST.NAME, Middle.NAME
    Add-Type -ErrorAction SilentlyContinue -ReferencedAssemblies $script:TypeAssem -TypeDefinition $testSource -Language CSharp 
  }
  $dataReader = Get-DataReader

  $invalidRecords = New-Object 'System.Collections.Generic.Dictionary[string,string]'

  $type = (New-Object "ColleagueSDK.DataContracts.$TableName").getType()
  switch ($PSCmdlet.ParameterSetName)
  {
    "p2" {
      $returned = .\Invoke-GenericMethod.ps1 $dataReader -methodName "BulkReadRecord" -typeParameters $type -methodParameters @($FilterKeys, [bool]$ReplaceTextVMs)
    }

    #"p3" {
    #}

    default {
      .\Invoke-GenericMethod.ps1 $dataReader -methodName "BulkReadRecord" -typeParameters $type -methodParameters @($Filter, [bool]$ReplaceTextVMs)
    }
  }


}

function Invoke-CTX{
  param($typeRequest, $typeResponse, $request)
  $trans = Get-TransactionInvoker
  .\Invoke-GenericMethod.ps1 $trans -methodName Execute -typeParameters $typeRequest, $typeResponse -methodParameters $request
}

function Get-AllApplications{
$AllApps = @"
//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated by the DSL/T4 Generator - Version 1.1
//     Last generated on 9/14/2015 11:04:52 AM by user roger.garrison
//
//     Type: CTX
//     Transaction ID: GET.ALL.APPLS
//     Application: UT
//     Environment: Development_rt
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

namespace ColleagueSDK.DataContracts
{
	[DataContract]
	public class Applications
	{
		[DataMember]
		[SctrqDataMember(AppServerName = "TV.APPLICATIONS", OutBoundData = true)]
		public string Application { get; set; }
	}

	[GeneratedCodeAttribute("Colleague Data Contract Generator", "1.1")]
	[DataContract]
	[ColleagueDataContract(ColleagueId = "GET.ALL.APPLS", GeneratedDateTime = "9/14/2015 11:04:52 AM", User = "roger.garrison")]
	[SctrqDataContract(Application = "UT", DataContractVersion = 1)]
	public class GetAllApplsRequest
	{
		/// <summary>
		/// Version
		/// </summary>
		[DataMember]
		public int _AppServerVersion { get; set; }


		public GetAllApplsRequest()
		{	
		}
	}

	[GeneratedCodeAttribute("Colleague Data Contract Generator", "1.1")]
	[DataContract]
	[ColleagueDataContract(ColleagueId = "GET.ALL.APPLS", GeneratedDateTime = "9/14/2015 11:04:52 AM", User = "roger.garrison")]
	[SctrqDataContract(Application = "UT", DataContractVersion = 1)]
	public class GetAllApplsResponse
	{
		/// <summary>
		/// Version
		/// </summary>
		[DataMember]
		public int _AppServerVersion { get; set; }

		[DataMember]
		[SctrqDataMember(AppServerName = "Grp:TV.APPLICATIONS", OutBoundData = true)]
		public List<Applications> Applications { get; set; }

		public GetAllApplsResponse()
		{	
			Applications = new List<Applications>();
		}
	}
}
"@

  Add-Type -ReferencedAssemblies $script:TypeAssem -TypeDefinition $AllApps -Language CSharp

  $request = New-Object ColleagueSDK.DataContracts.GetAllApplsRequest
  $typeRequest = $request.getType()
  $typeResponse = (New-Object ColleagueSDK.DataContracts.GetAllApplsResponse).getType()
  $apps = Invoke-CTX $typeRequest $typeResponse $request
  $apps.Applications | % Application
}

function Get-ApplicationEntities {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [string[]] $applicationNames
  )

  BEGIN {
    #region AllEntities
    $AllEntities = @"
//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated by the DSL/T4 Generator - Version 1.1
//
//     Type: CTX
//     Transaction ID: GET.APPL.ENTITIES
//     Application: UT
//     Environment: 
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

namespace ColleagueSDK.DataContracts
{
	[GeneratedCodeAttribute("Colleague Data Contract Generator", "1.1")]
	[DataContract]
	[ColleagueDataContract(ColleagueId = "GET.APPL.ENTITIES", GeneratedDateTime = "", User = "")]
	[SctrqDataContract(Application = "UT", DataContractVersion = 1)]
	public class GetApplEntitiesRequest
	{
		/// <summary>
		/// Version
		/// </summary>
		[DataMember]
		public int _AppServerVersion { get; set; }

		[DataMember(IsRequired = true)]
		[SctrqDataMember(AppServerName = "TV.APPLICATION", InBoundData = true)]        
		public string TvApplication { get; set; }

		public GetApplEntitiesRequest()
		{	
		}
	}

	[GeneratedCodeAttribute("Colleague Data Contract Generator", "1.1")]
	[DataContract]
	[ColleagueDataContract(ColleagueId = "GET.APPL.ENTITIES", GeneratedDateTime = "", User = "")]
	[SctrqDataContract(Application = "UT", DataContractVersion = 1)]
	public class GetApplEntitiesResponse
	{
		/// <summary>
		/// Version
		/// </summary>
		[DataMember]
		public int _AppServerVersion { get; set; }

		[DataMember]
		[SctrqDataMember(AppServerName = "TV.ENTITIES", OutBoundData = true)]        
		public List<string> TvEntities { get; set; }

		public GetApplEntitiesResponse()
		{	
			TvEntities = new List<string>();
		}
	}
}
"@
    #endregion AllEntities

    Add-Type -ReferencedAssemblies $script:TypeAssem -TypeDefinition $AllEntities -Language CSharp
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
    "p2" { $fileDetails = New-FileDetails $App $FileName -DetailMode }
    default{$fileDetails = New-FileDetails $App $FileName -FieldNames $FieldNames}
  }
  Write-Verbose "Create Entity Generator from New-EntityGeneratorInput"
  $entityDataModelGenerator = New-EntityGeneratorInput $fileDetails 
  
  $entityDataModelGenerator.dataContractNamespace = "ColleagueSDK.DataContracts"
  $entityDataModelGenerator.dateTime = Get-Date

  Write-Verbose "Transform the generator to C# code and return"
  return New-EntityTransform $entityDataModelGenerator
}
#endregion ColleagueInfo

#region VSExtUtilitiesRebuild
function New-EntityGeneratorInput{
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
          if (num2 -ge 19)
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


  Write-Verbose "Add Assembly System.Web, System.XML, Ellucian.WebServices.VS.DataModels and Ellucian.WebServices.VS.Ext"
  Add-Type -AssemblyName System.Web
  Add-Type -AssemblyName System.Xml
  Add-Type -Path "$($script:VSExtPath)\Ellucian.WebServices.VS.DataModels.dll"
  Add-Type -Path "$($script:VSExtPath)\Ellucian.WebServices.VS.Ext.dll"
  
  Write-Verbose "Get the Colleague Settings from the AppConfig"
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
  
  if(!$FieldNames){$FieldNames = New-Object Collections.Generic.List[String]}
  
  $returnVal = @()
  switch ($PSCmdlet.ParameterSetName)
  {
    "p3" {
        foreach($FileName in $FileNames)
        {
            $returnVal += [Ellucian.WebServices.VS.Ext.VSExtUtilities]::BuildFileDetails($colleagueEnv, $app, $filename, $filename, ([Collections.Generic.List[String]]$FieldNames), $true)
        }
    }
    default {
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
        
        $controllerName = ($assoc.EntityAssociationMembers.EntityAssociationMember | Where IsController)[0].Name
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
  
#endregion VSExtUtilitiesrebuild

Initialize-ColleagueService