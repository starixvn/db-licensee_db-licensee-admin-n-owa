/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateByCurrencySel]
	@PayerId		INT = 0
AS
/*
	Created: 20200205@Mason
	Task : Get charge rate by currency for payer
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20200205@Mason: Create SP [#Feature ID: 120005 Set billing term by currency]
		- 20200302@Mason: Support HID currency [#128856]
		- 20231002@Danny: Support Jollysport licensees [#FeatureID 193214]
		- 20250529@Danny: Get all the currency list [RedmineID: #226207]

	Params:
	+ @PayerId : 0 get all Party
		<> 0 specify Party
		
	Example:
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @ChargeDetail AS TABLE(ChargeID INT, PartyID INT, ProductID INT, BettypeRef INT,DI_Rate MONEY, Fromdate DATE, Todate DATE, ChargeType TINYINT)

	INSERT INTO @ChargeDetail (ChargeID, PartyID, ProductID, DI_Rate, Fromdate, Todate, ChargeType)
		SELECT
			ChargeID,
			ci.FromParty,
			ProductID,
			ci.Rate,
			Fromdate,
			Todate, 
			ChargeType
		FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		WHERE (@PayerId = 0 OR ci.FromParty = @PayerId)
		
	DECLARE @CurrencyInfo AS TABLE (CurrencyId INT, CurrencyCode VARCHAR(65), CurrencyName VARCHAR(20))
	INSERT INTO @CurrencyInfo(CurrencyId, CurrencyCode, CurrencyName)
	EXEC dbo.LA_PayerCurrencySel @PayerId = @PayerId
	
	UPDATE @CurrencyInfo SET CurrencyCode = 'HID' WHERE CurrencyId = 92

	-- Get charge rate by currency
	IF @PayerId = 0
	BEGIN

		UPDATE c
		SET c.CurrencyCode = CASE WHEN c.CurrencyId = 142 THEN 'USDT' WHEN c.CurrencyId IN (96,202, 206, 208, 209) THEN e.Code + ' (' + e.currency + ')' ELSE e.Code END,
			c.CurrencyName = e.currency
		FROM @CurrencyInfo c 
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON c.CurrencyId = e.ExchangeId

		DECLARE @result TABLE (ChargeId INT, CurrencyId INT, CurrencyCode VARCHAR(65), Rate MONEY, ChargeType TINYINT, PartyID INT)
		INSERT INTO @result(ChargeId, CurrencyId, CurrencyCode , Rate, ChargeType, PartyID)
		SELECT 
			cr.ChargeID		AS ChargeId, 
			cr.CurrencyID	AS CurrencyId, 
			ci.CurrencyCode	AS CurrencyCode, 
			cr.Rate			AS Rate,
			r.ChargeType	AS ChargeType,
			r.PartyID		AS PartyID
		FROM dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK)
		INNER JOIN @ChargeDetail r ON cr.ChargeID = r.ChargeID
		LEFT JOIN @CurrencyInfo ci ON ci.CurrencyId = cr.CurrencyID

		UPDATE c1
		SET c1.CurrencyCode = ex.Code + ' (' + ex.currency + ')'
		FROM @result c1
		INNER JOIN (
			SELECT PartyId, CurrencyCode, ChargeId
			FROM  @result
			GROUP BY PartyId, CurrencyCode, ChargeId
			HAVING COUNT(1) > 1
		) c2 ON c1.PartyId = c2.PartyId AND c1.CurrencyCode = c2.CurrencyCode AND c1.ChargeId = c2.ChargeId
		INNER JOIN bodb02.dbo.Exchange ex WITH(NOLOCK) ON ex.ExchangeId = c1.CurrencyId

		SELECT ChargeId, CurrencyId, CurrencyCode, Rate, ChargeType FROM @result

	END
	ELSE
	BEGIN
		
		SELECT 
			cr.ChargeID		AS ChargeId, 
			cr.CurrencyID	AS CurrencyId, 
			ci.Code + ' (' + ci.currency + ')'		AS CurrencyCode, 
			cr.Rate			AS Rate,
			r.ChargeType	AS ChargeType
		FROM dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK)
		INNER JOIN @ChargeDetail r ON cr.ChargeID = r.ChargeID
		LEFT JOIN bodb02.dbo.Exchange ci ON ci.ExchangeId = cr.CurrencyID
	END
END
GO