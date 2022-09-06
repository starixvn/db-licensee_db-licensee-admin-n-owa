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

	DECLARE @ChargeSettings AS TABLE (ChargeID INT, CurrencyId INT, Rate MONEY)

	DECLARE @ChargRateUpd AS TABLE (ChargeID INT, CurrencyId INT, Rate MONEY)

	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @DetailChargeRateSettingXml
	BEGIN TRY
		INSERT INTO @ChargeSettings(ChargeId, CurrencyId, Rate)
		SELECT ChargeID, CurrencyId, Rate
		FROM OPENXML(@idoc, 'ChargeSettings/ChargeSetting')
		WITH 
		(
			 ChargeId		INT   'ChargeId'
			,CurrencyId	    INT   'CurrencyId'
			,Rate			MONEY 'Rate'
		)
	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'There''s something wrong with Charge rate settings, update failed. Please try again.', @ErrCode = 504
		RETURN
	END CATCH
	EXEC sp_xml_removedocument @idoc

	-- Get Charge Rate to update 
	INSERT INTO @ChargRateUpd (ChargeID, CurrencyId, Rate)
	SELECT ChargeID, 0, CASE WHEN @MasterRate = Rate THEN 2 ELSE @MasterRate END -- Rate = 2 => not update
	FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE ChargeID = @ChargeID 

	INSERT INTO @ChargRateUpd (ChargeID, CurrencyId, Rate)
	SELECT c.ChargeID, c.CurrencyId, CASE WHEN ISNULL(cr.Rate, c.Rate - 1) = c.Rate THEN 2 ELSE c.Rate END
	FROM @ChargeSettings c	
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH(NOLOCK) ON cr.CurrencyID = c.CurrencyId
	WHERE cr.ChargeID = @ChargeID

	DELETE c
	FROM @ChargRateUpd c
	WHERE NOT EXISTS (SELECT 1 FROM @ChargRateUpd WHERE Rate <> 2)
	 
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
	DECLARE @SiteName VARCHAR(20) = '', @ProductId INT, @ProductName VARCHAR(50), @InputPT VARCHAR(MAX) = ''

	SELECT @ProductId = CASE WHEN ci.ProductID = 0  THEN 1 ELSE p.ProductID END, @ProductName = CASE WHEN ci.ProductId = 0 THEN 'Sportsbook' ELSE pr.ProductName END
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
		SELECT @ProductId AS '@PID', CurrencyId AS '@CID', 1 - Rate AS '@PT' -- -1 : not update
		FROM @ChargRateUpd 
		FOR XML PATH('PT'), ROOT('ROOT')
	))
	
	IF @SiteName <> '' AND @InputPT <> '' 
	BEGIN
		IF EXISTS (SELECT 1 FROM dbo.OAS_ChargeInfo WITH(NOLOCK) WHERE ChargeID = @ChargeID AND GETDATE() NOT BETWEEN FromDate AND ToDate)
		BEGIN
			SELECT @ErrCode = 101, @ErrMsg =  @ProductName + ': NAP PT update failed due to it''s not current charge rate'
			RETURN
		END

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
 
END
GO