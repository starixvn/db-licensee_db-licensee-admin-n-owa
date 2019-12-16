/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet,bodbLicenseeNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_Rpt_GroupLicensingFeeWinLoss]
	@PartyIDs				VARCHAR(5500)	= ''
	, @ProductCodes		VARCHAR(5500) = ''	
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME	
AS
/*  Created: Scofield.Huynh
	Date: 2018-12-04
	DB: DB052.bodb_licensee

	Revisions:
	   - 20181204@Scofield: create	
	   - 20190425@Parsons: Integrate-PP-Promotion-Prize [#109014] 
	   - 20191216@Parsons: PP tournament [#123958]
*/
BEGIN
	SET NOCOUNT ON	
	
	DECLARE @GD_Product INT = 11
	DECLARE @ChargeInfo TABLE(PartyID INT, LicenseeID INT, ProductID INT,Rate MONEY, Fromdate DATE, Todate DATE)
	CREATE TABLE #Data (rptDate DATE, PartyID INT, ProductID INT, Currency INT, BetTypeId INT, Winloss MONEY, AComm MONEY)
	CREATE TABLE #Report (PartyID INT, ProductID INT, CurrencyID INT, Company MONEY)						
	
	/* ChargeInfo */
	INSERT INTO @ChargeInfo(PartyID, LicenseeID, ProductID, Rate, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END, Fromdate, Todate		
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
	WHERE ChargeType <> 12 -- Exclude for GD Tips
	
	/* BA Product */
	DECLARE @BA_Product INT = 3
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = @BA_Product) > 0
	BEGIN
		INSERT INTO #Report (PartyID, ProductID, CurrencyID, Company)
		(
			SELECT ci.PartyID, b.ProductID, b.currencyID, -SUM((b.MemberWL * ci.Rate ) + b.CommissionA) AS Company
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @ChargeInfo ci 
				ON b.SiteID = ci.LicenseeID 
					AND b.ProductID = ci.ProductID
					AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = @BA_Product
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY ci.PartyID, b.ProductID, currencyID
		)
	END	

	/* CO Product */
	DECLARE @CO_Product INT = 25
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = @CO_Product) > 0
	BEGIN		
		INSERT INTO #Report (PartyID, ProductId, CurrencyID, Company)
		(
			SELECT
				d.PartyId,
				@CO_Product,
				d.Currency,				
				SUM(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) AS Company
			FROM (
					SELECT ci.PartyId, b.Winlostdate, b.Currency,											
							SUM(b.BuyBackAmt) AS BuyBackAmountSB,
							SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
							SUM(b.TicketPayout) AS TicketsPayout,					
							SUM(b.BuyBackAmt * ci.Rate) AS CashoutCommission	
					FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
						INNER JOIN @ChargeInfo ci ON b.SiteId = ci.LicenseeID AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate AND b.ProductID = ci.ProductId					
					WHERE b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate									
						AND (b.Currency <> 20)
						AND b.ProductID = @CO_Product
						AND b.RoleID = 1 -- Member
					GROUP BY ci.PartyId, b.Winlostdate, b.Currency			
			) d
			GROUP BY d.PartyId, d.Currency
		)
	END	
	
	/* GD Product */	
	DECLARE @GD_Tip SMALLINT = 1706
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = @GD_Product) > 0
	BEGIN
		INSERT INTO #Report (PartyID, ProductId, CurrencyID, Company)
		(
			SELECT ci.PartyID, @GD_Product, b.CurrencyID, SUM(-b.MemberWL * ci.Rate) AS Company
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @ChargeInfo ci 
				ON b.SiteID = ci.LicenseeID
				AND b.ProductID = ci.ProductID
				AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27,28)
				AND b.ProductID = @GD_Product
				AND b.Bettype <> @GD_Tip 				
			GROUP BY ci.PartyID, b.CurrencyID
		)		
	END

	/* PP Product */	
	DECLARE @PP_Product INT = 32,  
			@PPTournament SMALLINT = 4299,
			@PromotionPrize SMALLINT = 4300
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = @PP_Product) > 0
	BEGIN
	INSERT INTO #Report (PartyID, ProductId, CurrencyID, Company)
		(
			SELECT ci.PartyID, @PP_Product, b.CurrencyID, SUM(-b.MemberWL * ci.Rate) AS Company
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID 
										 AND b.ProductID = ci.ProductID 
										 AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND b.customercategory NOT IN (27,28)
				AND b.ProductID = @PP_Product
				AND b.Bettype NOT IN (@PPTournament, @PromotionPrize) 				
			GROUP BY ci.PartyID, b.CurrencyID
		)
	END

	/* Other Products */
	DECLARE @ExcludedProductIds TABLE(ProductId INT)
	INSERT INTO @ExcludedProductIds(ProductId) VALUES (@BA_Product), (@CO_Product), (@GD_Product), (@PP_Product)
	
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) > 0
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Winloss)
		(
			SELECT  b.rptDate, ci.PartyID, b.ProductID, b.currencyID, SUM(b.MemberWL)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyId, LicenseeId, ProductID FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci 
					ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27,28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY b.rptDate, ci.PartyID, b.ProductID, b.CurrencyID
		)

		INSERT INTO #Report (PartyID, ProductID, CurrencyID, Company)
		SELECT ci.PartyID, b.ProductID, b.Currency, SUM(-b.Winloss * ci.Rate) AS Company
		FROM #Data b WITH (NOLOCK)
		INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci 
			ON ci.PartyID = b.PartyID 
				AND b.ProductID = ci.ProductID				
				AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
		GROUP BY ci.PartyID, b.Currency, b.ProductID
	END	
	
	/* Exchange */
	DECLARE @Exchange AS TABLE (Currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(20), OriginalCurrencyCode VARCHAR(20))

	INSERT INTO @Exchange(Currency, CurrencyName, CurrencyCode, OriginalCurrencyCode)
	SELECT e.exchangeid, e.currency, e.Code, e.Code
	FROM bodb02.dbo.Exchange e WITH (NOLOCK)
	WHERE e.exchangeid IN (SELECT DISTINCT CurrencyID FROM #Report)
	
	UPDATE @Exchange
	SET CurrencyCode = (CASE Currency
					WHEN 51 THEN 'INH'
					WHEN 75 THEN 'PTU'
					WHEN 76 THEN 'PS'
					WHEN 77 THEN 'PTH' 
					ELSE CurrencyCode
				END)
	WHERE Currency IN (51, 75, 76, 77)

	UPDATE e
	SET CurrencyCode = e.CurrencyCode + '(' + CurrencyName + ')'
	FROM @Exchange e
	WHERE e.CurrencyCode IN (SELECT CurrencyCode FROM @Exchange GROUP BY CurrencyCode HAVING COUNT(1) > 1)	

	/* Add data for products with no ticket*/
	DECLARE @Currencies TABLE(CurrencyID INT, IsUsed BIT)
	DECLARE @TempCurrency INT	
	DECLARE @ChargeInfoPartyProducts TABLE(PartyId INT, ProductId INT, CurrencyID INT DEFAULT NULL)

	INSERT INTO @Currencies(CurrencyID)
	SELECT DISTINCT CurrencyID 
	FROM #Report
	
	INSERT @ChargeInfoPartyProducts(PartyId, ProductId)
	SELECT DISTINCT PartyId, ProductId
	FROM @ChargeInfo
	
	WHILE EXISTS (SELECT * FROM @Currencies WHERE IsUsed IS NULL)
	BEGIN
	   SET @TempCurrency = (SELECT TOP 1 CurrencyID FROM @Currencies WHERE IsUsed IS NULL)
	   
	   INSERT INTO @ChargeInfoPartyProducts(PartyId, ProductId, CurrencyID)
	   SELECT PartyId, ProductId, @TempCurrency
	   FROM @ChargeInfoPartyProducts
	   WHERE CurrencyID IS NULL

	   UPDATE @Currencies SET IsUsed = 1 WHERE CurrencyID = @TempCurrency
	END
	
	INSERT INTO #Report (PartyID, ProductID, CurrencyID, Company)
    SELECT tmp.PartyId, tmp.ProductId, tmp.CurrencyID, 0
    FROM 		 
	(
		SELECT c.PartyId, c.ProductId, c.CurrencyID
		FROM (SELECT * FROM @ChargeInfoPartyProducts WHERE CurrencyID IS NOT NULL) c
		LEFT JOIN #Report r 
			ON c.PartyId = r.PartyId 
				AND c.ProductId = r.ProductId
				AND c.CurrencyID = r.CurrencyID
		WHERE r.PartyId IS NULL		
	) tmp	
	
	/* Result */
	;WITH tmpResult AS (
		SELECT b.PartyID
			, CASE p.PartyName
				WHEN '18bb' THEN 'PIH'
				WHEN 'IBC'	THEN 'FDL'
				ELSE p.PartyName
				END AS PartyName
			, b.CurrencyID
			, ex.CurrencyCode AS CurrencyName
			, b.ProductId
			, prd.ProductName
			, CASE WHEN ex.OriginalCurrencyCode IN ('VND', 'IDR') THEN Company * 1000
					ELSE Company 
					END AS AmountToCompany
		FROM #Report b
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) 
			ON p.PartyID = b.PartyID
		LEFT JOIN LA_f_Products3rd('') prd
			ON prd.ProductId = b.ProductId
		LEFT JOIN @Exchange ex 
			ON b.CurrencyId = ex.Currency
	)
	SELECT PartyName, CurrencyName, ProductName, ProductId, Sum(AmountToCompany) AS AmountToCompany
	FROM tmpResult t
	GROUP BY PartyName, CurrencyName, ProductName, ProductId	
	
	/* Remove temp tables */
	DROP TABLE #Report
	DROP TABLE #Data
END
GO