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

	DECLARE @ProductListAll VARCHAR(500) = '',
			@ListParty VARCHAR(8000) = '',
			@MinDate DATE,
			@MaxDate DATE,
			@CurrentDate DATE
	SET @CurrentDate = CONVERT(DATE, GETDATE())
	
	DECLARE @ChargeInfo AS TABLE(ChargeId INT, PartyId INT, PartyName VARCHAR(100), ProductId INT, ProductName VARCHAR(100),
			BettypeRef INT,Rate MONEY, FromDate DATE, ToDate DATE, FirstBilling DATE, ExchangeID INT, ExchangeName VARCHAR(50), ChargeType TINYINT)
	CREATE TABLE #Temp_ChargeInfo(ChargeId INT, PartyID INT, ProductID INT, BettypeRef INT,Rate MONEY, Fromdate DATE, Todate DATE, ChargeType TINYINT)

	DECLARE @ChargeDetail AS TABLE(ChargeID INT, PartyID INT, ProductID INT, BettypeRef INT,DI_Rate MONEY, Fromdate DATE, Todate DATE, ChargeType TINYINT)

	--Get list licensee,
	SELECT	@ListParty = @ListParty + CAST(p.PartyID AS VARCHAR) + ','
	FROM	dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK)
				ON p.PartyID = pd.PartyID
	WHERE	PartyType = 1
			AND pd.IsDeposit = 1
			AND (@PayerId = 0
			OR p.PartyID = @PayerId)

	SET @ListParty = SUBSTRING(@ListParty, 0, LEN(@ListParty))
	
	--get list Product
	SELECT	@ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM	dbo.LA_f_Products3rd('')
	SET @ProductListAll = REPLACE(SUBSTRING(@ProductListAll, 0, LEN(@ProductListAll)), 'RB', '')

	--get Minium date, maximum date
	SELECT	@MinDate = MIN(ci.FromDate),
			@MaxDate = MAX(ci.ToDate)
	FROM	dbo.OAS_ChargeInfo ci WITH (NOLOCK)
	INNER	JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK)
				ON ci.ChargeID = cs.ChargeID
				AND cs.SystemID = 2

	INSERT INTO @ChargeDetail (ChargeID, PartyID, ProductID, BettypeRef, DI_Rate, Fromdate, Todate, ChargeType)
		SELECT
			ChargeID,
			PartyID,
			ProductID,
			CASE WHEN ProductID IN (14,17) THEN
					Bettype
				 ELSE 0 END
			AS BettypeRef,
			DI_Rate,
			Fromdate,
			Todate, 
			ChargeType
		FROM dbo.LA_f_ChargeInfo(@ListParty, @MinDate, @MaxDate, @ProductListAll, 'OA', 1)

	INSERT INTO #Temp_ChargeInfo (ChargeID, PartyID, ProductID, BettypeRef, Rate, Fromdate, Todate, ChargeType)
		SELECT 
			b.ChargeID,
			a.PartyID,
			a.ProductID,
			b.BettypeRef,
			b.DI_Rate,
			a.Fromdate,
			a.Todate, 
			a.ChargeType
		FROM (	SELECT 
						c.PartyID,
						c.ProductID,
						c.ChargeType,
						MAX(c.Fromdate) AS Fromdate,
						MAX(c.Todate) AS Todate
				FROM	@ChargeDetail c
				WHERE	@CurrentDate <= c.Todate
				GROUP BY	c.PartyID,
							c.ProductID, 
							c.ChargeType) a
		INNER JOIN @ChargeDetail b
			ON a.PartyID = b.PartyID
			AND a.ProductID = b.ProductID
			AND a.Fromdate = b.Fromdate
			AND a.Todate = b.Todate
			
	INSERT INTO @ChargeInfo (ChargeId, PartyId, PartyName, ProductId, ProductName, BettypeRef, Rate, FromDate, ToDate, FirstBilling, ExchangeID, ChargeType)
		SELECT 
			c.ChargeID,
			c.PartyID,
			CASE
				WHEN ISNULL(pd.BrandName, '') != '' THEN pd.BrandName
				ELSE p.PartyName
			END AS PartyName,
			c.ProductID,
			pr.ProductName,
			c.BettypeRef,
			c.Rate,
			c.Fromdate,
			c.Todate,
			CASE WHEN c.ProductID IN (14,17) THEN s.FirstOfBilling ELSE ci.FirstOfBilling END,
			pd.BaseCurrencyId,
			CASE WHEN c.ProductID IN (14,17) THEN s.ChargeType ELSE ci.ChargeType END
		FROM #Temp_ChargeInfo c
			INNER JOIN OAS_Party p WITH (NOLOCK) ON c.PartyID = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN dbo.LA_f_Products3rd('') pr ON c.ProductID = pr.ProductID
			INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON c.ChargeID = ci.ChargeID
			LEFT JOIN dbo.OAS_ChargeInfoSub s WITH(NOLOCK) ON ci.ChargeID = s.ChargeIdRef
		WHERE @CurrentDate <= c.Todate

	-- get terminated
	INSERT INTO @ChargeInfo (ChargeId, PartyId, PartyName, ProductId, ProductName, BettypeRef, Rate, FromDate, ToDate, FirstBilling, ExchangeID, ExchangeName, ChargeType)
	SELECT DISTINCT -1,
		d.PartyID,
		CASE
			WHEN ISNULL(pd.BrandName, '') != '' THEN pd.BrandName
			ELSE p.PartyName
		END AS PartyName,
		0,
		'Terminated',
		0,
		0,
		@MinDate,
		@MinDate,
		NULL,
		0,
		'',
		1
	FROM @ChargeDetail d
		INNER JOIN OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
	WHERE d.PartyID NOT IN (SELECT c.PartyId FROM @ChargeInfo c)

	-- product order
	DECLARE @ProductOrder TABLE(ProductId INT, OrderNumber SMALLMONEY)
	INSERT INTO @ProductOrder
	SELECT ProductId, CASE ProductId 
			WHEN 15/*CB*/ THEN 13.5 -- , make CB after BT and before MGCLC
			ELSE ProductId -- keep as it is
		END
	FROM dbo.LA_f_Products3rd('')

	DECLARE @CurrencyInfo AS TABLE (CurrencyId INT, CurrencyCode VARCHAR(20), CurrencyName VARCHAR(20))
	INSERT INTO @CurrencyInfo
	EXEC dbo.LA_PayerCurrencySel @PayerId = @PayerId
	
	--result
	;WITH Result AS (
		SELECT DISTINCT
			c.ChargeId		AS ChargeID,
			c.PartyId		AS PayerID,
			PartyName		AS PayerName,
			c.ProductId		AS ProductId,
			ProductName		AS ProductName,
			FirstBilling	AS FirstBilling,
			c.BettypeRef,
			c.Rate AS Rate,
			c.ExchangeID AS ExchangeID,
			c.ExchangeName AS ExchangeName,
			c.ChargeType
		FROM @ChargeInfo c
	)
	
	-- Get charge rate by currency
	SELECT 
		cr.ChargeID		AS ChargeId, 
		cr.CurrencyID	AS CurrencyId, 
		ci.CurrencyCode	AS CurrencyCode, 
		cr.Rate			AS Rate
	FROM dbo.LA_ChargeRateByCurrency cr 
	INNER JOIN Result r ON cr.ChargeID = r.ChargeID
	LEFT JOIN @CurrencyInfo ci ON ci.CurrencyId = cr.CurrencyID
	
	DROP TABLE #Temp_ChargeInfo
END
GO