/*<info serverAlias="DBLOG-bodb_CustomerLog" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[WriteLog_LogAction_Lic_GetActionID]
	@SPName		VARCHAR(200) = NULL
	,@ActionID	INT = 0 OUTPUT
AS

/*
	Created: 20190510@Percy
	DB: DBLOG.bodb_CustomerLog
	Task: Get ActionID by SP Name
        
	Revisions:
		- 20190510@Percy: Initialize SP [RedmineID: #103658]
*/

BEGIN
	SET NOCOUNT ON

	SELECT @ActionID = 0

	SELECT @ActionID = ISNULL(ActionId, 0)
	FROM dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = @SPName
END
GO