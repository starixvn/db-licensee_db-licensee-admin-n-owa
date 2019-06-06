/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesUpd]
	@HostingFeesId		INT,
	@HostingFeesName	VARCHAR(200),
	@HostingFeesTypeId	TINYINT,
	@BaseCurrencyId		INT	,
	@Description		NVARCHAR(200) = '',
	@XmlDetails			NVARCHAR(max),
	@UserID				INT,
	@LoginIP			VARCHAR (50)	= '',
	@ErrCode			INT				= 0  OUTPUT,
	@ErrMsg				NVARCHAR(1000)	= '' OUTPUT
AS
/*
	Created: 20160615@Bravo
	Task : Insert hosting fees settings
	DB: DBCUST.bodb_Licensee  

	Revisions:
		- 20160628@Bruce: Fix duplicate charge rate name
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]

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
		@logData	NVARCHAR(4000),
		@logDataOld	NVARCHAR(4000)

	IF EXISTS (SELECT 1 FROM dbo.LA_HostingFees WITH(NOLOCK) WHERE HostingFeesName = @HostingFeesName AND HostingFeesId != @HostingFeesId)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Charge Rate Name exists please try again!'
		RETURN
	END

	SET @logDataOld = CAST((SELECT
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
		FROM dbo.LA_HostingFees c WITH(NOLOCK) WHERE c.HostingFeesId = @HostingFeesId
		FOR XML PATH('z'), ROOT('r')
	) AS NVARCHAR(4000))

	SET @logData = CAST((SELECT
			@BaseCurrencyId		AS '@bc',
			@Description		AS '@ds',
			@HostingFeesName	AS '@hn',
			@HostingFeesTypeId	AS '@ht',
			@HostingFeesId		AS '@hi',
			CAST(@XmlDetails AS VARCHAR(2000)) AS '@dt'
		FOR XML PATH('z'), ROOT('r')
	) AS NVARCHAR(4000))

	-- Region: Backup
	DECLARE @BackupHostingFees TABLE(
		HostingFeesId		INT,
		HostingFeesName		VARCHAR(200),
		HostingFeesTypeId	TINYINT,
		BaseCurrencyId		INT,
		[Description]		NVARCHAR(200)
	)

	INSERT INTO @BackupHostingFees(HostingFeesId, HostingFeesName, HostingFeesTypeId, BaseCurrencyId, [Description])
	SELECT f.HostingFeesId, f.HostingFeesName, f.HostingFeesTypeId, f.BaseCurrencyId, f.[Description]
	FROM dbo.LA_HostingFees f WITH(NOLOCK)
	WHERE f.HostingFeesId = @HostingFeesId

	-- Region: update hosting fees
	UPDATE dbo.LA_HostingFees
	SET HostingFeesName = @HostingFeesName,
		HostingFeesTypeId = @HostingFeesTypeId,
		BaseCurrencyId = @BaseCurrencyId,
		[Description] = @Description
	WHERE HostingFeesId = @HostingFeesId
	-- EndRegion

	DECLARE @BackupFeesDetails AS TABLE (
		HostingFeesId	INT,
		BaseCurrencyId	INT	,
		VCMFrom			INT	,
		VCMTo			INT	,
		Amount			MONEY)

	INSERT INTO @BackupFeesDetails (HostingFeesId, BaseCurrencyId, VCMFrom, VCMTo, Amount)
	SELECT d.HostingFeesId, d.BaseCurrencyId, d.VCMFrom, d.VCMTo, d.Amount
	FROM dbo.LA_HostingFeesDetail d WITH(NOLOCK)
	WHERE d.HostingFeesId = @HostingFeesId
	-- EndRegion

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

		DELETE FROM dbo.LA_HostingFeesDetail WHERE HostingFeesId = @HostingFeesId

		INSERT INTO dbo.LA_HostingFeesDetail(HostingFeesId, BaseCurrencyId, VCMFrom, VCMTo, Amount)
		SELECT @HostingFeesId, f.BaseCurrencyId, f.VCMFrom, f.VCMTo, f.Amount
		FROM @FeesDetails f

		-- write log
		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

		EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@LicenseeID	= 0
			,@CurrencyID	= 0
			,@SPName		= 'LA_HostingFeesUpd'
			,@CustId		= 0
			,@Duration		= @duration
			,@Data			= @logData
			,@OldData		= @logDataOld
	END TRY
	BEGIN CATCH 
		-- Rollback
		UPDATE f
		SET f.HostingFeesName	= b.HostingFeesName,
			f.HostingFeesTypeId = b.HostingFeesTypeId,
			f.BaseCurrencyId	= b.BaseCurrencyId,
			f.[Description]		= b.[Description]
		FROM dbo.LA_HostingFees f
			INNER JOIN @BackupHostingFees b ON f.HostingFeesId = b.HostingFeesId

		DELETE FROM dbo.LA_HostingFeesDetail WHERE HostingFeesId = @HostingFeesId

		INSERT INTO dbo.LA_HostingFeesDetail(HostingFeesId, BaseCurrencyId, VCMFrom, VCMTo, Amount)
		SELECT @HostingFeesId, f.BaseCurrencyId, f.VCMFrom, f.VCMTo, f.Amount
		FROM @BackupFeesDetails f

		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 4
		RETURN
	END CATCH
	EXEC sp_xml_removedocument @idoc

END
GO