/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
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
		- 20200205@Mason: Create SP

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
		FROM dbo.OAS_ChargeInfo ci
		WHERE (@PayerId = 0 OR ci.FromParty = @PayerId)
		
	DECLARE @CurrencyInfo AS TABLE (CurrencyId INT, CurrencyCode VARCHAR(20), CurrencyName VARCHAR(20))
	INSERT INTO @CurrencyInfo
	EXEC dbo.LA_PayerCurrencySel @PayerId = @PayerId

	-- Get charge rate by currency
	SELECT 
		cr.ChargeID		AS ChargeId, 
		cr.CurrencyID	AS CurrencyId, 
		ci.CurrencyCode	AS CurrencyCode, 
		cr.Rate			AS Rate
	FROM dbo.LA_ChargeRateByCurrency cr 
	INNER JOIN @ChargeDetail r ON cr.ChargeID = r.ChargeID
	LEFT JOIN @CurrencyInfo ci ON ci.CurrencyId = cr.CurrencyID
END
GO