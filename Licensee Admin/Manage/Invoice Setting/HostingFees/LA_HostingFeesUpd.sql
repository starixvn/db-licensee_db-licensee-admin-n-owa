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
		- 20230530@Danny: Insert new log with more information [#FeatureID 175125]

	Params:
		+ @InvoiceSettingXML: '<HostingFees>
								  <HostingFee>
									<BaseCurrencyId>1</BaseCurrencyId>
									<VCMFrom>1</VCMFrom>
									<VCMTo>1</VCMTo>
									<Amount>1</Amount>
									<HostingFeesDetailId>616</HostingFeesDetailId>
								  </HostingFee>

								  <HostingFee>
									<BaseCurrencyId>1</BaseCurrencyId>
									<VCMFrom>1</VCMFrom>
									<VCMTo>1</VCMTo>
									<Amount>1</Amount>
									<HostingFeesDetailId>616</HostingFeesDetailId>
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
		@logData	NVARCHAR(MAX),
		@logDataOld	NVARCHAR(MAX),
		@ActionID	INT = 2001

	IF EXISTS (SELECT 1 FROM dbo.LA_HostingFees WITH(NOLOCK) WHERE HostingFeesName = @HostingFeesName AND HostingFeesId != @HostingFeesId)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Charge Rate Name exists please try again!'
		RETURN
	END

	SELECT @logDataOld = 
	(
		SELECT	   
				f.HostingFeesName 'gs.crn', 
				CASE WHEN e.ExchangeId = 142 THEN 'USDT' ELSE e.Code END 'gs.e',
				rs.rs 'rs'
		
		FROM dbo.LA_HostingFees f WITH(NOLOCK)
			INNER JOIN CustDB.dbo.exchange e WITH(NOLOCK) ON e.ExchangeId = f.BaseCurrencyId
			CROSS APPLY (
				SELECT 
				(
					SELECT 	d.HostingFeesDetailId FakeID,
							t.HostingFeesTypeName + ' - ' + CASE WHEN e1.ExchangeId = 142 THEN 'USDT' ELSE e1.Code END t, 
							CASE WHEN f.HostingFeesTypeId = 2 THEN FORMAT(d.VCMFrom,'N','en-us') ELSE 'N/A'  END amf,
							CASE WHEN f.HostingFeesTypeId = 2 THEN CASE WHEN d.VCMTo = 1000000000 THEN 'Unlimited' ELSE FORMAT(d.VCMTo,'N','en-us') END ELSE 'N/A' END amt,
							FORMAT(d.Amount,'N','en-us') am
					FROM dbo.LA_HostingFeesDetail d WITH(NOLOCK)
					INNER JOIN dbo.LA_HostingFeesTypes t WITH(NOLOCK) ON f.HostingFeesTypeId = t.HostingFeesTypeId
					INNER JOIN CustDB.dbo.exchange e1 WITH(NOLOCK) ON e1.ExchangeId = d.BaseCurrencyId
					WHERE d.HostingFeesId = f.HostingFeesId FOR JSON PATH
				) rs
			) rs
		WHERE f.HostingFeesId = @HostingFeesId  FOR JSON PATH,  WITHOUT_ARRAY_WRAPPER 
	)

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

	DECLARE @BackupFeesDetails AS TABLE (
		HostingFeesId	INT,
		BaseCurrencyId	INT	,
		VCMFrom			INT	,
		VCMTo			INT	,
		Amount			MONEY,
		HostingFeesDetailId INT
		)

	INSERT INTO @BackupFeesDetails (HostingFeesId, BaseCurrencyId, VCMFrom, VCMTo, Amount, HostingFeesDetailId)
	SELECT d.HostingFeesId, d.BaseCurrencyId, d.VCMFrom, d.VCMTo, d.Amount, d.HostingFeesDetailId
	FROM dbo.LA_HostingFeesDetail d WITH(NOLOCK)
	WHERE d.HostingFeesId = @HostingFeesId
	-- EndRegion

	DECLARE @FeesDetails AS TABLE (
		BaseCurrencyId	INT,
		VCMFrom			INT,
		VCMTo			INT,
		Amount			MONEY,
		HostingFeesDetailId INT
		)
		
	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @XmlDetails

	INSERT INTO @FeesDetails(BaseCurrencyId, VCMFrom, VCMTo, Amount, HostingFeesDetailId)
	SELECT BaseCurrencyId, VCMFrom, VCMTo, Amount, HostingFeesDetailId
	FROM OPENXML(@idoc, 'HostingFees/HostingFee')
	WITH (
		BaseCurrencyId	INT		'BaseCurrencyId',
		VCMFrom			INT		'VCMFrom',
		VCMTo			INT		'VCMTo',
		Amount			MONEY	'Amount',
		HostingFeesDetailId INT 'HostingFeesDetailId'
	)

	-- Region: update hosting fees
	UPDATE dbo.LA_HostingFees
	SET HostingFeesName = @HostingFeesName,
		HostingFeesTypeId = @HostingFeesTypeId,
		BaseCurrencyId = @BaseCurrencyId,
		[Description] = @Description
	WHERE HostingFeesId = @HostingFeesId
	-- EndRegion

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 4
		RETURN
	END

	;MERGE dbo.LA_HostingFeesDetail WITH (ROWLOCK, UPDLOCK) AS t
	USING @FeesDetails s ON t.HostingFeesDetailId = s.HostingFeesDetailId AND t.HostingFeesId = @HostingFeesId
	WHEN MATCHED THEN
		UPDATE SET t.HostingFeesId = @HostingFeesId
			, t.BaseCurrencyId = s.BaseCurrencyId
			, t.VCMFrom = s.VCMFrom
			, t.VCMTo = s.VCMTo
			, t.Amount = s.Amount
	WHEN NOT MATCHED BY TARGET THEN
		INSERT(HostingFeesId, BaseCurrencyId, VCMFrom, VCMTo, Amount)
		VALUES(@HostingFeesId, BaseCurrencyId, VCMFrom, VCMTo,Amount)
	WHEN NOT MATCHED BY SOURCE AND t.HostingFeesId = @HostingFeesId THEN DELETE;

	IF @@ERROR <> 0
	BEGIN
		-- Rollback
		UPDATE f
		SET f.HostingFeesName	= b.HostingFeesName,
			f.HostingFeesTypeId = b.HostingFeesTypeId,
			f.BaseCurrencyId	= b.BaseCurrencyId,
			f.[Description]		= b.[Description]
		FROM dbo.LA_HostingFees f
			INNER JOIN @BackupHostingFees b ON f.HostingFeesId = b.HostingFeesId
		
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 4
		RETURN
	
	END

	-- write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	SELECT @logData = 
	(
		SELECT	   
				f.HostingFeesName 'gs.crn', 
				CASE WHEN e.ExchangeId = 142 THEN 'USDT' ELSE e.Code END 'gs.e',
				rs.rs 'rs'
		
		FROM dbo.LA_HostingFees f WITH(NOLOCK)
			INNER JOIN CustDB.dbo.exchange e WITH(NOLOCK) ON e.ExchangeId = f.BaseCurrencyId
			CROSS APPLY (
				SELECT 
				(
					SELECT 	d.HostingFeesDetailId FakeID,
							t.HostingFeesTypeName + ' - ' + CASE WHEN e1.ExchangeId = 142 THEN 'USDT' ELSE e1.Code END t, 
							CASE WHEN f.HostingFeesTypeId = 2 THEN FORMAT(d.VCMFrom,'N','en-us') ELSE 'N/A'  END amf,
							CASE WHEN f.HostingFeesTypeId = 2 THEN CASE WHEN d.VCMTo = 1000000000 THEN 'Unlimited' ELSE FORMAT(d.VCMTo,'N','en-us') END ELSE 'N/A' END amt,
							FORMAT(d.Amount,'N','en-us') am
					FROM dbo.LA_HostingFeesDetail d WITH(NOLOCK)
					INNER JOIN dbo.LA_HostingFeesTypes t WITH(NOLOCK) ON f.HostingFeesTypeId = t.HostingFeesTypeId
					INNER JOIN CustDB.dbo.exchange e1 WITH(NOLOCK) ON e1.ExchangeId = d.BaseCurrencyId
					WHERE d.HostingFeesId = f.HostingFeesId FOR JSON PATH
				) rs
			) rs
		WHERE f.HostingFeesId = @HostingFeesId  FOR JSON PATH,  WITHOUT_ARRAY_WRAPPER 
	)

	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'LA_HostingFeesUpd'
		,@CustId		= @HostingFeesId
		,@Duration		= @duration
		,@TrackingValue2 = @logData
		,@TrackingValue  = @logDataOld
		,@ActionID		 = @actionID

	EXEC sp_xml_removedocument @idoc

END
GO