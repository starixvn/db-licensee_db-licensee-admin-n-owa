USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesDel]
	@HostingFeesId	INT,
	@UserID			INT,
	@LoginIP		VARCHAR (50)	= '',
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20160615@Bravo
	 Task : Delete hosting fees settings
	 DB: DB052.bodb_Licensee  
   
	 Revisions:
	 Params:
		
	 Example:
		EXEC dbo.[LA_HostingFeesDel] 1
*/
BEGIN	
	SET NOCOUNT ON

	-- For writing log
	DECLARE 
		@startRun	DATETIME = GETDATE(),
		@endRun		DATETIME,
		@duration	INT,
		@logData	NVARCHAR(4000)

	IF EXISTS (SELECT 1 FROM dbo.LA_HostingFeesSetting WITH(NOLOCK) WHERE HostingFeesId = @HostingFeesId)
	BEGIN
		SELECT 	@ErrMsg = 'This setting is being used.', @ErrCode = 2	
		RETURN
	END

	SET @logData = CAST((SELECT
			c.BaseCurrencyId	AS '@bc',
			c.[Description]		AS '@ds',
			c.HostingFeesId		AS '@hi',
			c.HostingFeesName	AS '@hn',
			c.HostingFeesTypeId	AS '@ht',
			(
				SELECT dt.* FROM dbo.LA_HostingFeesDetail dt WITH(NOLOCK)
				WHERE dt.HostingFeesId = @HostingFeesId
				FOR XML PATH('item')
			) AS '@dt'
		FROM dbo.LA_HostingFees c WHERE c.HostingFeesId = @HostingFeesId
		FOR XML PATH('z'), ROOT('r')
	) AS NVARCHAR(4000))

	DELETE FROM dbo.LA_HostingFees WHERE HostingFeesId = @HostingFeesId
	DELETE FROM dbo.LA_HostingFeesDetail WHERE HostingFeesId = @HostingFeesId
	
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

	-- Write Log
	DECLARE @SpName VARCHAR(100) = 'LA_HostingFeesDel'
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
GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesDel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_HostingFeesDel] TO bodbAdminNet 

 