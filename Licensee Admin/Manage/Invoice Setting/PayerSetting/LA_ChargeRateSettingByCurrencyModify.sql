/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateSettingByCurrencyModify]
	  @ChargeID				INT
	, @MasterRate			MONEY
	, @DetailChargeRateSettingXml		NVARCHAR (MAX)
	, @UserID				INT
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*
	 Created: 20191202@Parsons
	 Task: 
	 DB: DBCUST.bodb_Licensee

	 Revisions:
		- 20191202@Parsons: Setup billing terms by Currency  [#120005]

	 Params:
		+ @DetailChargeRateSettingXml: '<ChargeSettings>
								  <ChargeSetting>
									<ChargeId>1994</ChargeId>
									<CurrencyId>1</CurrencyId>
									<Rate>0.2</Rate>
								  </ChargeSetting>
								  <ChargeSetting>
									<ChargeId>1994</ChargeId>
									<CurrencyId>1</CurrencyId>
									<Rate>0.3</Rate>
								  </ChargeSetting>
								</ChargeSettings>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ChargeSettings AS TABLE (
		ChargeID		INT,
		CurrencyId		INT,
		Rate			MONEY)

	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @DetailChargeRateSettingXml
	BEGIN TRY
		INSERT INTO @ChargeSettings(ChargeId, CurrencyId, Rate)
		SELECT ChargeID, CurrencyId, Rate
		FROM OPENXML(@idoc, 'ChargeSettings/ChargeSetting')
		WITH (
			 ChargeId		INT				'ChargeId'
			, CurrencyId	INT				'CurrencyId'
			, Rate			MONEY			'Rate'
		)
	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'There''s something wrong with Charge rate settings, update failed. Please try again.', @ErrCode = 504
		RETURN
	END CATCH
	EXEC sp_xml_removedocument @idoc

	-- Update master rate
	UPDATE OAS_ChargeInfo
	SET Rate = @MasterRate
	WHERE ChargeID = @ChargeID

	-- Insert charge rate by currency
	SELECT * FROM @ChargeSettings
	;MERGE [dbo].[LA_ChargeRateByCurrency] WITH(ROWLOCK, UPDLOCK) AS t
	USING @ChargeSettings AS s
	ON (t.ChargeId = s.ChargeID AND t.CurrencyID = s.CurrencyID)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(ChargeId, CurrencyID, Rate)
				VALUES(s.ChargeId, s.CurrencyID, s.Rate)
	WHEN MATCHED
		THEN UPDATE SET Rate = s.Rate
	WHEN NOT MATCHED BY SOURCE AND t.ChargeId = @ChargeId
		THEN DELETE;
END
GO