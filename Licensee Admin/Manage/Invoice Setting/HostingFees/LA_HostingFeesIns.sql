USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesIns]
	@HostingFeesName	VARCHAR(200),
	@HostingFeesTypeId	TINYINT,
	@BaseCurrencyId		INT	,
	@Description		NVARCHAR(200) = '',
	@XmlDetails			NVARCHAR(max),
	@UserID				INT,
	@LoginIP			VARCHAR (50)	= '',
	@ErrCode			INT				= 0		OUTPUT,
	@ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*
	Created: 20160615@Bravo
	Task : Insert hosting fees settings
	DB: DB052.bodb_Licensee

	Revisions:
		20160624@Bruce: Check duplicate charge rage name
	Params:
		+ @InvoiceSettingXML: '<HostingFees>
								  <HostingFee>
									<BaseCurrencyId>1</BaseCurrencyId>
									<VCMFrom>1</VCMFrom>
									<VCMTo>1</VCMTo>
									<Amount>1</Amount>
								  </HostingFee>

								  <HostingFee>
									<BaseCurrencyId>1</BaseCurrencyId>
									<VCMFrom>1</VCMFrom>
									<VCMTo>1</VCMTo>
									<Amount>1</Amount>
								  </HostingFee>
								</HostingFees>'
*/
BEGIN
	SET NOCOUNT ON

	-- For writing log
	DECLARE 
		@startRun	DATETIME = GETDATE(),
		@endRun		DATETIME,
		@duration	INT,
		@logData	NVARCHAR(4000)

	DECLARE @HostingFeeId INT

	-- Region: Insert hosting fees
	IF EXISTS (SELECT 1 FROM dbo.LA_HostingFees WITH(NOLOCK) WHERE HostingFeesName = @HostingFeesName)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Charge Rate Name exists please try again!'
		RETURN
	END

	SET @logData = CAST((SELECT
			@BaseCurrencyId		AS '@bc',
			@Description		AS '@ds',
			@HostingFeesName	AS '@hn',
			@HostingFeesTypeId	AS '@ht',
			CAST(@XmlDetails AS VARCHAR(2000)) AS '@dt'
		FOR XML PATH('z'), ROOT('r')
	) AS NVARCHAR(4000))

	INSERT INTO dbo.LA_HostingFees(HostingFeesName, HostingFeesTypeId, BaseCurrencyId, [Description])
	VALUES (@HostingFeesName, @HostingFeesTypeId, @BaseCurrencyId, @Description)

	SET @HostingFeeId = SCOPE_IDENTITY()
	-- EndRegion

	-- Region: Insert hosting fees details
	DECLARE @FeesDetails AS TABLE (
		BaseCurrencyId	INT,
		VCMFrom			INT,
		VCMTo			INT,
		Amount			MONEY)

	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @XmlDetails
	BEGIN TRY
		INSERT INTO @FeesDetails(BaseCurrencyId, VCMFrom, VCMTo, Amount)
		SELECT BaseCurrencyId, VCMFrom, VCMTo, Amount
		FROM OPENXML(@idoc, 'HostingFees/HostingFee')
		WITH (
			BaseCurrencyId	INT		'BaseCurrencyId',
			VCMFrom			INT		'VCMFrom',
			VCMTo			INT		'VCMTo',
			Amount			MONEY	'Amount'
		)

		INSERT INTO dbo.LA_HostingFeesDetail(HostingFeesId, BaseCurrencyId, VCMFrom, VCMTo, Amount)
		SELECT @HostingFeeId, f.BaseCurrencyId, f.VCMFrom, f.VCMTo, f.Amount
		FROM @FeesDetails f

	END TRY
	BEGIN CATCH
		-- Rollback
		DELETE FROM dbo.LA_HostingFees WHERE HostingFeesId = @HostingFeeId
		DELETE FROM dbo.LA_HostingFeesDetail WHERE HostingFeesId = @HostingFeeId

		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 3
		RETURN
	END CATCH
	EXEC sp_xml_removedocument @idoc

	-- EndRegion

	-- Region: Write Log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

	DECLARE @SpName VARCHAR(100) = 'LA_HostingFeesIns'
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
			, @Data = @logData
			, @OldData = ''
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP
			@UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = @logData
			, @TrackingValue2 = ''
			, @duration = @duration
	END CATCH
	-- EndRegion
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesIns] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_HostingFeesIns] TO bodbAdminNet 

