$Sessions = [hashtable]::Synchronized( @{} )

# key-value store for entire runspace
$Shared = [hashtable]::Synchronized( @{} )

$ThreadController | Add-Member -MemberType ScriptMethod -Name "Session" -Value {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        $ScriptBlock = {},
        [bool] $Sync = $false
    )

    $Action = if( $ScriptBlock.ToString().Trim() -ne "" ){
        switch ($ScriptBlock.GetType().Name) {
            "ScriptBlock" {}
            "String" {
                Try{
                    [scriptblock]::Create( $ScriptBlock ) | Out-Null
                } Catch {
                    throw [System.ArgumentException]::new( "ScriptBlock must be a ScriptBlock or Valid ScriptBlock String!", "ScriptBlock" )
                }
            }
            default {
                throw [System.ArgumentException]::new( "ScriptBlock must be a ScriptBlock or String!", "ScriptBlock" )
            }
        }

        @(
            "`$session_name = `"$Name`"",
            "`$script_block = { $ScriptBlock }",
            {
                If( $Sessions.ContainsKey( $session_name ) ){
                    $Session = $Sessions[ $session_name ]
                } Else {

                    $Session = New-Object -TypeName PSObject -Property @{
                        Name = $session_name
                        Module = New-Module -ScriptBlock ([scriptblock]::Create(@(
                            "`$SessionName = `"$session_name`"",
                            {
                                # key-value store for session within runspace
                                $Store = [hashtable]::Synchronized( @{} )
                            }.ToString()
                            "Export-ModuleMember"
                        ) -join "`n")) -Name $session_name
                    }

                    $Session | Add-Member -MemberType ScriptMethod -Name "Invoke" -Value {
                        param(
                            [Parameter(Mandatory = $true)]
                            $ScriptBlock
                        )

                        If( $ScriptBlock.GetType().Name -eq "ScriptBlock" ){
                            $ScriptBlock = $ScriptBlock.Ast.GetScriptBlock()
                        } Elseif( $ScriptBlock.GetType().Name -eq "String" ){
                            Try {
                                $ScriptBlock = [scriptblock]::Create( $ScriptBlock )
                            } Catch {
                                throw [System.ArgumentException]::new( "Session.Invoke() ScriptBlock must be a ScriptBlock or Valid ScriptBlock String!", "Action" )
                            }
                        } Else {
                            throw [System.ArgumentException]::new( "Session.Invoke() ScriptBlock must be a ScriptBlock or Valid ScriptBlock String!", "Action" )
                        }

                        $this.Module.Invoke( $ScriptBlock )
                    }.Ast.GetScriptBlock()

                    $Session | Add-Member -MemberType NoteProperty -Name "ThreadController" -Value $ThreadController -Force
                    $Session | Add-Member -MemberType ScriptProperty -Name "Store" -Value {
                        $this.ThreadController.Dispatcher.VerifyAccess()
                        $this.Invoke({ $Store })
                    }.Ast.GetScriptBlock()

                    $Sessions.Add( $session_name, $Session ) | Out-Null
                }

                $session_name = $null

                $Session.Invoke( $script_block, $Sync )
            }.ToString()
        ) -join "`n"
    } Else {
        ""
    }

    $output = $this.Invoke( $Action, $Sync )
    
    $output | Add-Member `
        -MemberType NoteProperty `
        -Name "Session" `
        -Value $Name `
        -Force
    
    $output | Add-Member `
        -MemberType ScriptMethod `
        -Name "Invoke" `
        -Value {
            param(
                [parameter(Mandatory = $true)]
                $ScriptBlock,
                [bool] $Sync = $false
            )

            switch ($ScriptBlock.GetType().Name) {
                "ScriptBlock" {}
                "String" {}
                default {
                    throw [System.ArgumentException]::new( "ScriptBlock must be a ScriptBlock or String!", "ScriptBlock" )
                }
            }
        
            Try {
                $this.ThreadController.Session( $this.Session, $ScriptBlock, $Sync )
            } Catch {
                if( $_.Exception.Message -like "*null-valued expression*" ){
                    throw [System.Exception]::new( "Thread controller does not exist or was disposed!", $_.Exception )
                } Else {
                    throw $_
                }
            }
        }.Ast.GetScriptBlock() -Force

    $output
}.Ast.GetScriptBlock()