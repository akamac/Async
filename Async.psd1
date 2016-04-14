@{
	RootModule = 'Async.psm1'
	ModuleVersion = '1.0.3'
	GUID = '1b03fd50-6a66-451a-bbd2-27346bcf2dde'
	Author = 'Alexey Miasoedov'
	CompanyName = 'Intermedia'
	Copyright = '(c) 2016 Alexey Miasoedov. All rights reserved.'
	Description = 'Framework for asynchronous command execution with runspace pools'
	PowerShellVersion = '4.0'
	# PowerShellHostName = ''
	# PowerShellHostVersion = ''
	# DotNetFrameworkVersion = ''
	# CLRVersion = ''
	# ProcessorArchitecture = ''
	# RequiredModules = @{ModuleName = 'MiscFunctions'; ModuleVersion = '1.0.0'}
	# RequiredAssemblies = @()
	# ScriptsToProcess = @()
	# TypesToProcess = @()
	# FormatsToProcess = @()
	# NestedModules = @()
	FunctionsToExport = #'*-*' # only Verb-Noun; avoid helper functions
		'Create-RunspacePool',
		'Invoke-Async',
		'Receive-AsyncResults'
	CmdletsToExport = '*'
	VariablesToExport = '*'
	AliasesToExport = '*'
	# ModuleList = @()
	FileList = 'Async.psm1','StubHost.cs'
	# PrivateData = ''
	# HelpInfoURI = ''
	# DefaultCommandPrefix = ''
}