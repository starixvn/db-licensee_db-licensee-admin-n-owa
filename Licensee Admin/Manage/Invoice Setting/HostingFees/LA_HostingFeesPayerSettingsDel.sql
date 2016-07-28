USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
	DB: DB052.bodb_Licensee

	Revisions:
		201600708@Bruce: create
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
		FROM dbo.LA_HostingFeesSetting c WHERE FromParty = @PayerId
		FOR XML PATH('z'), ROOT('r')
	) AS NVARCHAR(4000))

	DELETE FROM dbo.LA_HostingFeesSetting WHERE FromParty = @PayerId

	-- Write Log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

	DECLARE @SpName VARCHAR(100) = 'LA_HostingFeesPayerSettingsDel'
	DECLARE @ActionID INT = ISNULL((
		SELECT ActionId
		FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
		WHERE SPName = @SpName
	),0)
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog
			@UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = @SpName
			, @CustId = 0
			, @ActionId = @ActionID
			, @Duration = @duration
			, @Data = ''
			, @OldData = @logData
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP
			@UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = ''
			, @TrackingValue2 = @logData
			, @duration = @duration
	END CATCH	
	--
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesPayerSettingsDel] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_HostingFeesPayerSettingsDel] TO bodbAdminNet
