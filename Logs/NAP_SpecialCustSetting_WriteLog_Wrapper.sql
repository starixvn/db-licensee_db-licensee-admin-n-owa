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
	Created: Dom
	Date: 2014-08-29
	Task: Insert log customer setting
	DB: DBCUST.bodb_CustomerLog, DBLOG.bodb_CustomerLog
        
	Revisions:
		- 20140829@Dom: Initialize SP
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ActionID INT = 0
	SELECT	@ActionID = ActionId
	FROM DBLOG.bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = @SPName
	
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