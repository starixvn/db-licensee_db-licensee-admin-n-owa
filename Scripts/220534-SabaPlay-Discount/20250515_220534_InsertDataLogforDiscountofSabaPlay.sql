/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20250515@Eddie
	DB: DBLOG.bodb_CustomerLog
	Task: Add log for "Discount Group for SabaPlay" [RedmineID: #220534]
*/
USE bodb_CustomerLog
GO

DECLARE @ActionTypeId TINYINT, @ActionTypeNameEN NVARCHAR(50) = N'Discount Group for SabaPlay', @Items VARCHAR(MAX), @ActionID SMALLINT

SET @Items = 
'{"Items": [{"Alias":"gs","Item":"General Setting"},
{"Alias":"gn","Item":"Group Name"},
{"Alias":"af","Item":"Applied From"},
{"Alias":"at","Item":"Applied To"},
{"Alias":"dr","Item":"Discount Rate"},
{"Alias":"e","Item":"Exchange"},
{"Alias":"pa","Item":"Applied Product(s)"},
{"Alias":"oig","Item":"Operator(s) in Group"}  ]}'

SELECT @ActionTypeId = MAX(ActionTypeID) + 1
FROM dbo.LA_LogActionType WITH (NOLOCK)

SELECT @ActionID = MAX(ActionID) + 1
FROM dbo.LA_LogAction WITH (NOLOCK)
WHERE ActionNameEN LIKE '%Discount%'

IF ISNULL(@ActionTypeId, 0) = 0 OR ISNULL(@ActionID, 0) = 0
	RETURN

-- LA_LogActionType
INSERT INTO dbo.LA_LogActionType (ActionTypeID, ActionTypeNameEN)
SELECT t.ActionTypeID, t.ActionTypeNameEN
FROM (
		VALUES(@ActionTypeId, @ActionTypeNameEN)
) AS t(ActionTypeID, ActionTypeNameEN)
	LEFT JOIN dbo.LA_LogActionType lt WITH (NOLOCK) ON lt.ActionTypeID = t.ActionTypeID
	                                               AND lt.ActionTypeNameEN = t.ActionTypeNameEN
WHERE lt.ActionTypeID IS NULL 
  AND lt.ActionTypeNameEN IS NULL
  
-- LA_LogAction
INSERT INTO dbo.LA_LogAction(ActionID, ActionTypeID, ActionNameEN, Items)
SELECT ActionID, ActionTypeID, ActionNameEN, Items
FROM (
		VALUES (@ActionID, @ActionTypeId, 'Add Discount Group for SabaPlay', @Items)
			 , (@ActionID + 1, @ActionTypeId, 'Update Discount Group for SabaPlay', @Items)
			 , (@ActionID + 2, @ActionTypeId, 'Remove Discount Group for SabaPlay', @Items)
) AS t(ActionID, ActionTypeID, ActionNameEN, Items)