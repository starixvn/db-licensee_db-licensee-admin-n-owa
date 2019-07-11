/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesPayerSettingsDel]
	@PayerId	INT,
	@UserID		INT,
	@LoginIP	VARCHAR (50)	= '',
	@ErrCode	INT				= 0		OUTPUT,
	@ErrMsg		NVARCHAR(1000)	= ''	OUTPUT
AS
/*
	Created: 201600713@Bruce
	Task : Delete all hosting fees settings of payer
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20160708@Bruce: create
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
	
	Params:

	Example:
		EXEC dbo.LA_HostingFeesPayerSettingsDel 14
*/
BEGIN	
	SET NOCOUNT ON

	-- For writing log
	DECLARE 
		@startRun	DATETIME = GETDATE(),
		@endRun		DATETIME,
		@duration	INT,
		@logData	NVARCHAR(4000)

	SET @logData = CAST((SELECT
			c.ChargeId			AS '@ci',
			c.SettingType 		AS '@st',
			c.ParentId 			AS '@pi',
			c.FromParty 		AS '@fp',
			c.ToParty 			AS '@tp',
			c.FromDate 			AS '@fd',
			c.ToDate 			AS '@td',
			c.ProductName 		AS '@pn',
			c.FirstBilling 		AS '@fb',
			c.BasisOfBilling 	AS '@bb',
			c.BaseCurrencyId 	AS '@bc',
			c.HostingFeesId 	AS '@hi',
			c.BasedMinimunFees 	AS '@bf',
			c.Remark 			AS '@rm'
		FROM dbo.LA_HostingFeesSetting c WITH(NOLOCK) WHERE FromParty = @PayerId
		FOR XML PATH('z'), ROOT('r')
	) AS NVARCHAR(4000))

	DELETE FROM dbo.LA_HostingFeesSetting WHERE FromParty = @PayerId

	-- Write Log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_HostingFeesPayerSettingsDel'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= ''
		,@OldData		= @logData
END
GO