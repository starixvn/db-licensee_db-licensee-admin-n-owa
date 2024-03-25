/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20231026@Danny
	DB: DBLOG.bodb_CustomerLog
	Task: Add log for Upload payment RedmineId #193656
*/
USE [bodb_CustomerLog]
GO

INSERT INTO [dbo].[LA_LogActionType](ActionTypeID, ActionTypeNameEN)
 VALUES (21, 'Payment')


INSERT INTO LA_LogAction (ActionID, ActionTypeID, ActionNameEN, Items)
VALUES (2101, 21, 'Upload payment', '')

UPDATE LA_LogAction 
SET 
Items = 
'{"Items": [
{"Alias": "gi", "Item": "General Info"},
{"Alias": "p", "Item": "Payer"},
{"Alias": "r", "Item": "RefNo"},
{"Alias": "pi", "Item": "Payment Info"},
{"Alias": "pn", "Item": "Payment No"},
{"Alias": "rd", "Item": "Received Date (mm/dd/yyyy)"},
{"Alias": "fc", "Item": "From Customer"},
{"Alias": "tc", "Item": "To Customer"},
{"Alias": "a", "Item":  "Amount"},
{"Alias": "fa", "Item": "From Amount"},
{"Alias": "ta", "Item": "To Amount"},
{"Alias": "ar", "Item": "Actual Rate"},
{"Alias": "rp", "Item": "Rebate Payment (Y/N)"},
{"Alias": "d" ,"Item": "Description"}]}
'
WHERE ACtionID = 2101








