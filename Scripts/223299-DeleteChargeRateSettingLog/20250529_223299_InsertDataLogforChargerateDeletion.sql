/*<info serverAlias="DBLOG-bodb_CustomerLog"></info>*/
/*
	Created: 20250529@Eddie
	DB: DBLOG.bodb_CustomerLog
	Task: Add log for deleting the charge rate setting [RedmineID: #223299]
*/
USE bodb_CustomerLog
GO

DECLARE @ActionID SMALLINT, @Max_ActionID SMALLINT, @ActionNameEN NVARCHAR(50) = N'Remove Product Charge Rate Setting'

SELECT @ActionID = MAX(ActionID) + 1, @Max_ActionID = MAX(ActionID)
FROM dbo.LA_LogAction WITH (NOLOCK)
WHERE ActionNameEN LIKE '%Charge Rate Setting%'

IF ISNULL(@ActionID, 0) = 0
	RETURN

-- LA_LogAction
INSERT INTO dbo.LA_LogAction(ActionID, ActionTypeID, ActionNameEN, Items)
SELECT @ActionID, ActionTypeID, @ActionNameEN, Items
FROM dbo.LA_LogAction WITH (NOLOCK)
WHERE ActionID = @Max_ActionID