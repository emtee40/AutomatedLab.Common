function New-TfsBuildDefinition
{
    [CmdletBinding(DefaultParameterSetName = 'Cred')]
    param
    (
        [Parameter(Mandatory)]
        [string]
        $InstanceName,

        [Parameter(Mandatory)]
        [string]
        $CollectionName,

        [ValidateRange(1, 65535)]
        [uint32]
        $Port,

        [string]
        $ApiVersion = '2.0',

        [Parameter(Mandatory)]
        [string]
        $ProjectName,

        [Parameter(Mandatory)]
        [string]
        $DefinitionName,

        [string]
        $QueueName,

        [hashtable[]]
        $BuildTasks, # Not very nice and needs to be replaced as soon as I find out how to retrieve all build step guids

        [switch]
        $UseSsl,

        [Parameter(Mandatory, ParameterSetName = 'Cred')]
        [pscredential]
        $Credential,
        
        [Parameter(Mandatory, ParameterSetName = 'Pat')]
        [string]
        $PersonalAccessToken
    )

    $requestUrl = if ($UseSsl) {'https://' } else {'http://'}
    $requestUrl += if ( $Port  -gt 0)
    {
        '{0}{1}/{2}/{3}/_apis/build/definitions?api-version={4}' -f $InstanceName, ":$Port", $CollectionName, $ProjectName, $ApiVersion
    }
    else
    {
        '{0}/{1}/{2}/_apis/build/definitions?api-version={3}' -f $InstanceName, $CollectionName, $ProjectName, $ApiVersion
    }

    $parameters = Sync-Parameter -Command (Get-Command Get-TfsAgentQueue) -Parameters $PSBoundParameters
    $parameters.Remove('ApiVersion') # preview-API is called
    $queue = Get-TfsAgentQueue @parameters | Select-Object -First 1

    if (-not $queue)
    {
        $parameters = Sync-Parameter -Command (Get-Command New-TfsAgentQueue) -Parameters $PSBoundParameters
        $parameters.Remove('ApiVersion') # preview-API is called
        New-TfsAgentQueue @parameters
    }

    $projectParameters = Sync-Parameter -Command (Get-Command Get-TfsProject) -Parameters $PSBoundParameters
    $project = Get-TfsProject @projectParameters

    $repoParameters = Sync-Parameter -Command (Get-Command Get-TfsGitRepository) -Parameters $PSBoundParameters
    $repo = Get-TfsGitRepository @repoParameters

    $buildDefinition = @{
        "name"       = $DefinitionName
        "type"       = "build"
        "quality"    = "definition"
        "queue"      = @{
            "id" = $queue.id
        }
        "build"      = $BuildTasks
        "repository" = @{
            "id"            = $repo.id
            "type"          = "tfsgit"
            "name"          = $repo.name
            "defaultBranch" = "refs/heads/master"
            "url"           = $repo.remoteUrl
            "clean"         = $false
        }
        "options"    = @(
            @{
                "enabled"    = $true
                "definition" = @{
                    "id" = (New-Guid).Guid
                }
                "inputs"     = @{
                    "parallel"  = $false
                    multipliers = '["config","platform"]'
                }
            }
        )
        "variables"  = @{
            "forceClean" = @{
                "value"         = $false
                "allowOverride" = $true
            }
            "config"     = @{
                "value"         = "debug, release"
                "allowOverride" = $true
            }
            "platform"   = @{
                "value"         = "any cpu"
                "allowOverride" = $true
            }
        }
        "triggers"   = @()
    }

    $requestParameters = @{
        Uri         = $requestUrl
        Method      = 'Post'
        ContentType = 'application/json'
        Body        = ($buildDefinition | ConvertTo-Json -Depth 42)
        ErrorAction = 'Stop'
    }

    if ($Credential)
    {
        $requestParameters.Credential = $Credential
    }
    else
    {
        $requestParameters.Headers = @{ Authorization = Get-TfsAccessTokenString -PersonalAccessToken $PersonalAccessToken }
    }

    $result = Invoke-RestMethod @requestParameters
}
