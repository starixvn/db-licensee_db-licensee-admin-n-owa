/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[NAP_SpecialCustSetting_WriteLog_Wrapper]
    @UserId		INT,
	@IP			VARCHAR(15),
    @LicenseeID INT,
    @CurrencyID INT,
    @SPName		VARCHAR(50),
    @CustId		INT,
    @Duration	INT,
    @Data		XML,
    @OldData	XML
AS

/*
	Created: 20190510@Percy
	DB: DBCUST-bodb_CustomerLog, DBLOG.bodb_CustomerLog
	Task: SpecialCustSetting WriteLog
        
	Revisions:
		- 20190510@Percy: Initialize SP [RedmineID: #103658]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @ActionID INT = 0

	EXEC DBLOG.bodb_CustomerLog.dbo.WriteLog_LogAction_Lic_GetActionID @SPName = @SPName, @ActionID = @ActionID OUTPUT
	
	BEGIN TRY
		EXEC DBLOG.bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog
			@UserId			= @UserId
			,@IP			= @IP
			,@LicenseeID	= @LicenseeID
			,@CurrencyID	= @CurrencyID
			,@SPName		= @SPName
			,@CustId		= @CustId
			,@ActionId		= @ActionId
			,@Duration		= @Duration
			,@Data			= @Data
			,@OldData		= @OldData
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog
			@UserId			= @UserId
			,@IP			= @IP
			,@LicenseeID	= @LicenseeID
			,@CurrencyID	= @CurrencyID
			,@SPName		= @SPName
			,@CustId		= @CustId
			,@ActionId		= @ActionId
			,@Duration		= @Duration
			,@Data			= @Data
			,@OldData		= @OldData
	END CATCH
END
GO