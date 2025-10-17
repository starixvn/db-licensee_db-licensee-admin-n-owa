/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20250515@Eddie
	DB: DBLOG.bodb_CustomerLog
	Task: Add log for "Discount Group for SabaPlay" [RedmineID: #220534]
*/
USE bodb_CustomerLog
GO

INSERT INTO LA_LogActionType (ActionTypeID, ActionTypeNameEN)
SELECT 24, 'Rebate Group for SabaPlay'

DECLARE @p_Items NVARCHAR(MAX) =
'{
  "Items": [{"Alias": "gs","Item": "General Setting"},
    {"Alias": "gn","Item": "Group Name"},
    {"Alias": "af","Item": "Applied From"},
    {"Alias": "at","Item": "Applied To"},
    {"Alias": "r","Item": "Rate"},
    {"Alias": "rt","Item": "Rebate Type"},
    {"Alias": "rm","Item": "Remark"},
    {"Alias": "pa","Item": "Applied Product(s)"},
    {"Alias": "pig","Item": "Operator(s) in Group"}]
}'

INSERT INTO LA_LogAction (ActionID,	ActionTypeID,	ActionNameEN,	Items)
SELECT 2400, 24, 'Add Rebate Group for SabaPlay', @p_Items
UNION ALL SELECT 2401, 24, 'Update Rebate Group for SabaPlay', @p_Items
UNION ALL SELECT 2402, 24, 'Remove Rebate Group for SabaPlay', @p_Items

