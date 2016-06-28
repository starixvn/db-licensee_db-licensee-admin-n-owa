USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
	DB: DB052.bodb_Licensee  

	Revisions:
		20160628@Bruce: Fix duplicate charge rate name
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

	IF EXISTS (SELECT 1 FROM dbo.LA_HostingFees WHERE HostingFeesName = @HostingFeesName AND HostingFeesId != @HostingFeesId)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Charge Rate Name exists please try again!'
		RETURN
	END

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
	FROM dbo.LA_HostingFees f
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
	FROM dbo.LA_HostingFeesDetail d
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
GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesUpd] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_HostingFeesUpd] TO bodbAdminNet 

