 <#
    Connect-AzAccount -ServicePrincipal `
        -ApplicationId $svcPrincipalAppId  `
        -Tenant $tenantId  `
        -CertificateThumbprint $svcPrincipalThumbprint
    #>

Connect-AzAccount

#************** Parameters ********************************************************************************************************************
$subscriptionId = ""
$resourceGroupName = ""
$sbusPrimaryNamespace = ""
$sbusSecondaryNamespace = ""
$sbusAliasName = ""
$partnerId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.ServiceBus/namespaces/$sbusPrimaryNamespace"
#***********************************************************************************************************************************************

function Wait-ForNamespaceProvisioning {
    param (
        [string]$resourceGroupName,
        [string]$namespaceName
    )
    
    $maxRetries = 30
    $retryCount = 0
    $delay = 60  # Delay in seconds between retries
    
    do {
        $namespace = Get-AzServiceBusNamespace -ResourceGroupName $resourceGroupName -NamespaceName $namespaceName
        if ($namespace.ProvisioningState -eq "Succeeded") {
            Write-Output "Namespace $namespaceName is provisioned."
            return
        }
        
        Write-Output "Namespace $namespaceName is still in provisioning state: $($namespace.ProvisioningState). Waiting..."
        Start-Sleep -Seconds $delay
        $retryCount++

    } while ($namespace.ProvisioningState -ne "Succeeded" -and $retryCount -lt $maxRetries)
    
    if ($namespace.ProvisioningState -ne "Succeeded") {
        throw "Namespace $namespaceName did not reach 'Succeeded' state within the allotted time."
    }
}

function Wait-ForNamespaceGeoProvisioning {
    param (
        [string]$resourceGroupName,
        [string]$namespaceName
    )
    
    $maxRetries = 30
    $retryCount = 0
    $delay = 60  # Delay in seconds between retries
    
    do {
        $namespace = Get-AzServiceBusGeoDRConfiguration -ResourceGroupName $resourceGroupName -NamespaceName $namespaceName
        if ($namespace.ProvisioningState -eq "Succeeded") {
            Write-Output "Namespace $namespaceName is geo provisioned."
            return
        }
        
        if($null -eq $namespace){ 
            Write-Output "Namespace $namespaceName is geo provisioned."
            return 
        }
        
        Write-Output "Namespace $namespaceName is still in geo provisioning state: $($namespace.ProvisioningState). Waiting..."
        Start-Sleep -Seconds $delay
        $retryCount++

    } while ($namespace.ProvisioningState -ne "Succeeded" -and $retryCount -lt $maxRetries)
    
    if ($namespace.ProvisioningState -ne "Succeeded") {
        throw "Namespace $namespaceName did not reach 'Succeeded' state within the allotted time."
    }
}

function Wait-ForNamespaceAndGeoProvisining {
    param (
        [string]$resourceGroupName,
        [string]$PrimaryNamespace,
        [string]$SecondaryNamespace
    )

    Wait-ForNamespaceProvisioning -resourceGroupName $resourceGroupName -namespaceName $PrimaryNamespace
    Wait-ForNamespaceProvisioning -resourceGroupName $resourceGroupName -namespaceName $SecondaryNamespace

    Wait-ForNamespaceGeoProvisioning -resourceGroupName $resourceGroupName -namespaceName $PrimaryNamespace
    Wait-ForNamespaceGeoProvisioning -resourceGroupName $resourceGroupName -namespaceName $SecondaryNamespace

    return
}

#************** Initiate failover ***************************************************************************************************************

Wait-ForNamespaceAndGeoProvisining -resourceGroupName $resourceGroupName -PrimaryNamespace $sbusPrimaryNamespace -SecondaryNamespace $sbusSecondaryNamespace

Write-Output "`nFailing Over : Azure Service Bus $sbusPrimaryNamespace ...`n"

Set-AzServiceBusGeoDRConfigurationFailOver `
    -Name $sbusAliasName `
    -ResourceGroupName $resourceGroupName `
    -NamespaceName $sbusSecondaryNamespace `

Wait-ForNamespaceAndGeoProvisining -resourceGroupName $resourceGroupName -PrimaryNamespace $sbusPrimaryNamespace -SecondaryNamespace $sbusSecondaryNamespace

Write-Output "`nDeleting all queues in the primary $sbusPrimaryNamespace ..."

#$queueNames = @()
$queues = Get-AzServiceBusQueue -ResourceGroupName $resourceGroupName -NamespaceName $sbusPrimaryNamespace
foreach ($queue in $queues) {
    #$queueNames += $queue.Name
    Remove-AzServiceBusQueue `
        -ResourceGroupName $resourceGroupName `
        -NamespaceName $sbusPrimaryNamespace `
        -QueueName $queue.Name

    Write-Host "Deleted queue: $($queue.Name)"
}

Wait-ForNamespaceAndGeoProvisining -resourceGroupName $resourceGroupName -PrimaryNamespace $sbusPrimaryNamespace -SecondaryNamespace $sbusSecondaryNamespace

Write-Output "`nSetting the alias back after failover ..."

New-AzServiceBusGeoDRConfiguration `
    -Name $sbusAliasName `
    -NamespaceName $sbusSecondaryNamespace `
    -ResourceGroupName $resourceGroupName `
    -PartnerNamespace $partnerId

Wait-ForNamespaceAndGeoProvisining -resourceGroupName $resourceGroupName -PrimaryNamespace $sbusPrimaryNamespace -SecondaryNamespace $sbusSecondaryNamespace

Write-Output "`nService Bus failover process completed successfully !!"

#************** DONE *****************************************************************************************************************************

Disconnect-AzAccount
