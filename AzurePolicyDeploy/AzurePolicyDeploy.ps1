param([Parameter(Mandatory=$true)][string] $rootDirectory,
      [string] $subscriptionId,
      [string] $managementGroupName,
      [string] $resourceGroupName)

Write-Verbose "Entering script AzurePolicyDeploy.ps1"

# Set working directory to path specified by rootDirectory var
Set-Location -Path $rootDirectory -PassThru

if(!$subscriptionId -and !$managementGroupName)
{
    Throw "Unable to create policy: `$(SubscriptionId) '$subscriptionId' or `$(ManagementGroupName) '$managementGroupName' were not provided. Either may be provided, but not both."
}

if ($subscriptionId -and $managementGroupName)
{
    Throw "Unable to create policy: `$(SubscriptionId) '$subscriptionId' and `$(ManagementGroupName) '$managementGroupName' were both provided. Either may be provided, but not both."
}

if ($managementGroupName -and $resourceGroupName)
{
    Throw "Unable to create policy: `$(ManagementGroupName) '$managementGroupName' and `$(ResourceGroupName) '$resourceGroupName' were both provided. Either may be provided, but not both."
}

$azureRMModule = (Get-Module -Name AzureRM)
if ($managementGroupName -and (-not $azureRMModule -or $azureRMModule.version -lt 6.4))
{
    Throw "For creating policy as management group, Azure PS installed version should be equal to or greater than 6.4"
}

foreach($parentDir in Get-ChildItem -Directory)
{
    foreach($childDir in Get-ChildItem -Path $parentDir -Directory)
    {
        $configFile = "$parentDir\$childDir\policy.config.json"
        $rulesFile = "$parentDir\$childDir\policy.rules.json"

        $policyName  = (Get-Content $configFile | ConvertFrom-Json).config.policyName.value
        $policyDisplayName = (Get-Content $configFile | ConvertFrom-Json).config.policyDisplayName.value
        $policyDescription = (Get-Content $configFile | ConvertFrom-Json).config.policyDescription.value
        $assignmentName = (Get-Content $configFile | ConvertFrom-Json).config.assignmentName.value
        $assignmentDisplayName = (Get-Content $configFile | ConvertFrom-Json).config.assignmentDisplayName.value
        $assignmentDescription = (Get-Content $configFile | ConvertFrom-Json).config.assignmentDescription.value
        $policySetName = (Get-Content $configFile | ConvertFrom-Json).config.policySetName.value

        $cmdletParameters = @{Name=$policyName; Policy=$rulesFile; Mode='Indexed'}

        if ($policyDisplayName)
        {
            $cmdletParameters += @{DisplayName=$policyDisplayName}
        }

        if ($policyDescription)
        {
            $cmdletParameters += @{Description=$policyDescription}
        }

        if ($subscriptionId)
        {
            $cmdletParameters += @{SubscriptionId=$subscriptionId}
        }

        if ($managementGroupName)
        {
            $cmdletParameters += @{ManagementGroupName=$managementGroupName}
        }

        &New-AzureRmPolicyDefinition @cmdletParameters

        if ($managementGroupName)
        {
            $scope = "/providers/Microsoft.Management/managementGroups/$managementGroupName"
            $searchParameters = @{ManagementGroupName=$managementGroupName}
        }
        else
        {
            if (!$subscriptionId)
            {
                $subscription = Get-AzureRmContext | Select-Object -Property Subscription
                $subscriptionId = $subscription.Id
            }

            $scope = "/subscriptions/$subscriptionId"
            $searchParameters = @{SubscriptionId=$subscriptionId}
            
            if ($resourceGroupName)
            {
                $scope += "/resourceGroups/$resourceGroupName"
            }
        }

        $cmdletParameters = @{Name=$assignmentName; Scope=$scope}
        if ($assignmentDisplayName)
        {
            $cmdletParameters += @{DisplayName=$assignmentDisplayName}
        }

        if ($assignmentDescription)
        {
            $cmdletParameters += @{Description=$assignmentDescription}
        }

        if ($policyName)
        {
            $policyDefinition = Get-AzureRmPolicyDefinition @searchParameters | Where-Object { $_.Name -eq $policyName }
            if (!$policyDefinition)
            {
                Write-Error "Unable to create policy assignment: policy definition $policyName does not exist"
                exit 1
            }

            $cmdletParameters += @{PolicyDefinition=$policyDefinition}
        }

        if ($policySetName)
        {
            $policySetDefinition = Get-AzureRmPolicySetDefinition @searchParameters | Where-Object { $_.Name -eq $policySetName }
            if (!$policySetDefinition)
            {
                Write-Error "Unable to create policy assignment: policy set definition $policySetName does not exist"
                exit 1
            }

            $cmdletParameters += @{PolicySetDefinition=$policySetDefinition}
        }

        &New-AzureRmPolicyAssignment @cmdletParameters
    }
}

Write-Verbose "Leaving script AzurePolicyDeploy.ps1"
