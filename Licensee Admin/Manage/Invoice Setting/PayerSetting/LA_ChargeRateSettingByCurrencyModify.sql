/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[LA_ChargeRateSettingByCurrencyModify]
	 @ChargeID						INT
	,@MasterRate					MONEY
	,@DetailChargeRateSettingXml	NVARCHAR (MAX)
	,@UserID						INT
	,@LoginIP						VARCHAR (50) = ''
	,@ErrCode						INT = 0 OUTPUT
	,@ErrMsg						NVARCHAR(1000) = '' OUTPUT
AS
/*
	 Created: 20191202@Parsons
	 Task: 
	 DB: DBCUST.bodb_Licensee

	 Revisions:
		- 20191202@Parsons: Setup billing terms by Currency  [#120005]
		- 20220831@Malcolm: Automate the PT adjustment when the charge rate is changed [RemineID: #171705]

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

	DECLARE @ChargeSettings AS TABLE (ChargeID INT, CurrencyId INT, Rate DECIMAL(19,4))

	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @DetailChargeRateSettingXml
	BEGIN TRY
		INSERT INTO @ChargeSettings(ChargeId, CurrencyId, Rate)
		SELECT ChargeID, CurrencyId, Rate
		FROM OPENXML(@idoc, 'ChargeSettings/ChargeSetting')
		WITH 
		(
			 ChargeId		INT			  'ChargeId'
			,CurrencyId	    INT			  'CurrencyId'
			,Rate			DECIMAL(19,4) 'Rate'
		)
	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'There''s something wrong with Charge rate settings, update failed. Please try again.', @ErrCode = 504
		RETURN
	END CATCH
	EXEC sp_xml_removedocument @idoc

	-- Update master rate
	UPDATE OAS_ChargeInfo WITH(ROWLOCK)
	SET Rate = @MasterRate
	WHERE ChargeID = @ChargeID

	-- Insert charge rate by currency
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

	-- Update PT on NAP
	DECLARE @SiteName VARCHAR(20) = '', @ProductId INT, @InputPT VARCHAR(MAX)

	SELECT @ProductId = CASE WHEN ci.ProductID = 0  THEN 1 ELSE p.ProductID END
	FROM OAS_ChargeInfo ci WITH(NOLOCK)
		LEFT JOIN dbo.Product3rd pr WITH(NOLOCK) ON pr.Productid = ci.ProductID
		LEFT JOIN DBPRO.bodb02.dbo.Products p WITH (NOLOCK) ON p.ProductPrefix = pr.ProductPrefix
	WHERE ChargeID = @ChargeID

	SELECT @SiteName = l.LicenseeName 
	FROM OAS_ChargeInfo ci WITH(NOLOCK) 
		INNER JOIN dbo.OAS_Party p  WITH(NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN dbo.Licensees l WITH(NOLOCK) ON l.LicenseeID = p.OldRefID
	WHERE ChargeID IN (SELECT TOP 1 ChargeID FROM @ChargeSettings) AND l.IsDeposit = 1

	SELECT @InputPT = CONVERT(VARCHAR(MAX),
	(
		SELECT @ProductId AS '@PID', CurrencyId AS '@CID', 1 - Rate AS '@PT'
		FROM @ChargeSettings 
		FOR XML PATH('PT'), ROOT('ROOT')
	))
 
	EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_PTSettingUpd 
		@Site = @SiteName
		,@InputPT = @InputPT
		,@UserID = @UserID
		,@IP = @LoginIP
		,@ErrCode = @ErrCode
		,@ErrMsg = @ErrMsg

	IF @ErrCode <> 0
		RETURN
END
GO