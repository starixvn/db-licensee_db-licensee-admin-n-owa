/*<info serverAlias="DBCUST-bodb_CustomerLog,DBLOG-bodb_CustomerLog" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[NAP_SpecialCustSetting_WriteLog]
    @UserId		INT,
	@IP			VARCHAR(15),
    @LicenseeID INT,
    @CurrencyID INT,
    @SPName		VARCHAR(50),
    @CustId		INT,
    @ActionId	INT,
    @Duration	INT,
    @Data		NVARCHAR(MAX),
    @OldData	NVARCHAR(MAX)
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

	INSERT INTO dbo.Userlog_LicenseeSetting (UserId,IP,LicenseeID,CurrencyID,SPName,CustId,ActionId,Duration,Data,OldData)
	SELECT @UserId,@IP,@LicenseeID,@CurrencyID,@SPName,@CustId,@ActionId,@Duration,CONVERT(XML, @Data),CONVERT(XML, @OldData)
END
GO