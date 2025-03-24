# Creating Working BC Container

* copy path to `Create-WorkingContainer.ps1`


* call script with PowerShell

`. $scriptPath `

## Troubleshooting

* if script gets stuck (or throws error) on **Downloading packages from feeds** step - make sure:

* * User has access to read Packages from dependent organizations

* * `az login` was made after user got suitable rights

* * If you are using **Azure.CLI** for first time, check first steps needed by opening Azure DevOPS *Artifacts* in browser -> Connect to Feed -> Universal packages -> Get the tools (currently you also need to run `az extension add --name azure-devops`)
