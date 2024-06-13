/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20240619@Danny
	DB: DBLOG.bodb_CustomerLog
	Task: Add new log setting RedmineId #206143
*/
USE [bodb_CustomerLog]
GO


UPDATE LA_LogAction
SET Items = 
'{"Items": [{"Alias":"gs","Item":"General Setting"}, 
{"Alias":"gn","Item":"Group Name"}, 
{"Alias":"af","Item":"Applied From"}, 
{"Alias":"at","Item":"Applied To"}, 
{"Alias":"r","Item":"Rate"}, 
{"Alias":"rt","Item":"Rebate Type"}, 
{"Alias":"rm","Item":"Remark"}, 
{"Alias":"pa","Item":"Applied Product(s)"}, 
{"Alias":"pig","Item":"Payer(s) in Group"},
{"Alias":"ca","Item":"Applied Currency(s)"}
]}'
 WHERE ActionTypeID = 17