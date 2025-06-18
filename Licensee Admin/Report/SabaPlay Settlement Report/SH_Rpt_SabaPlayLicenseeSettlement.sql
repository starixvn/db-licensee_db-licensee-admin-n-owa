/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[SH_Rpt_SabaPlayLicenseeSettlement]
	@OperatorID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@ProductIDs		VARCHAR(MAX)
	,@BaseCurrencyName	VARCHAR(10)		= 'GBP'
	,@Environment		VARCHAR(50)		= 'LOCAL'
	,@RatioNote			VARCHAR(MAX)    = NULL OUTPUT
AS
/*  Created: 20250403@Danny
	Task : Report - SabaPlay Licensee Settlement Report
	DB: DBLIC.bodb_licensee
		
	Revisions:
		- 20250403@Danny: create new sp [RedmineID: #217741]
		- 20250506@Danny: use MemberTurnover column instead [RedmineID: #225394]
		- 20250520@Eddie: return futher discount rate [RedmineID: #220534]
		- 20250527@Danny: handle USDT currency code [RedmineID: #228187]
		- 20250618@Danny: return note for ratio [RedmineID: #229968]
	
	Param's Explanation:

	EXEC LA_Rpt_SabaPlayLicenseeSettlement @OperatorID = 721, @FromDate = '2025-02-01', @ToDate = '2025-02-28', @ProductIDs = '1,3', @BaseCurrencyName = 'EUR'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE = @FromDate, @TDate DATE = @ToDate, @PartyId INT, @CurrencyRatio VARCHAR(MAX)

	DECLARE @tmp_Product TABLE (ProductID INT)
	INSERT INTO @tmp_Product(ProductID)
	SELECT CAST(value AS INT) FROM STRING_SPLIT(@ProductIDs,',')

	SELECT @PartyId = PartyId
	FROM dbo.OAS_Party WITH (NOLOCK)
	WHERE ISNULL(OldRefID, 0) = @OperatorID

	SELECT @CurrencyRatio = CurrencyRatio
	FROM bodb_LicenseeReport.dbo.SabaPlay_Operators WITH(NOLOCK) WHERE SiteID = @OperatorID

	DROP TABLE IF EXISTS #Exchange
	CREATE TABLE #Exchange
	(
		ExchangeDate			DATE,
		ExchangeId				INT,
		CurrencyCode			VARCHAR(65),
		Rate					FLOAT,
		BaseExchangeRate		FLOAT
	)
	INSERT INTO #Exchange(ExchangeDate, ExchangeId, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeId, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	SELECT @ToDate 				 AS WinLostDate
		  ,sp.CurrencyCode 		 AS CurrencyName
		  ,ex.Rate				 AS ExchangeRate
		  ,sp.ProductID    		 AS ProductID
		  ,sp.ProductName  		 AS ProductName
		  ,sp.LicenseeChargeRate AS LicenseeChargeRate
		  ,ISNULL(ds.rate, 0)    AS DiscountRate

		  ,SUM(ISNULL(sp.BetCount,0)) 			  AS Betcount
		  ,SUM(ISNULL(sp.MemberTurnover,0)) 	  AS Turnover
		  ,SUM(ISNULL(sp.MemberWinLoss,0)) 		  AS GrossWin_CustomerWinloss
		  ,SUM(ISNULL(sp.LicenseeContribution,0)) AS GrossWin_Contribution
		  ,SUM(ISNULL(sp.LicenseeGrossWin,0)) 	  AS GrossWin_Total
		  ,SUM(ISNULL(sp.LicenseeWinLoss,0)) 	  AS LicenseeWinLoss

		  ,SUM(ISNULL(sp.LicenseeGrossWinAfterChargeRate,0)) AS GrossWin_ChargeRate
		  ,SUM(ISNULL(sp.LicenseeContribution,0)) 			 AS LicenseeContribution
		  ,SUM(ISNULL(sp.LicenseeJackpot,0)) 				 AS LicenseeJackpot
		  ,SUM(ISNULL(sp.LicenseePromotion,0)) 				 AS LicenseePromotion
		  ,SUM(ISNULL(sp.FinalLicensingFee,0)) 				 AS LicenseeTotal
		  ,SUM(ISNULL(sp.FinalLicensingFee,0) * ex.Rate) 	 AS Equivalent

		  ,SUM(ISNULL(sp.MemberNetTurnover,0) * ex.Rate) 	 AS TurnoverBase
		  ,SUM(ISNULL(sp.MemberWinLoss,0) * ex.Rate) 		 AS GrossWin_CustomerWinlossBase
		  ,SUM(ISNULL(sp.LicenseeContribution,0) * ex.Rate)  AS GrossWin_ContributionBase
		  ,SUM(ISNULL(sp.LicenseeGrossWin,0) * ex.Rate) 	 AS GrossWin_TotalBase
		  ,SUM(ISNULL(sp.LicenseeWinLoss,0) * ex.Rate) 		 AS LicenseeWinLossBase

		  ,SUM(ISNULL(sp.LicenseeGrossWinAfterChargeRate,0) * ex.Rate) AS GrossWin_ChargeRateBase
		  ,SUM(ISNULL(sp.LicenseeContribution,0) * ex.Rate) 		   AS LicenseeContributionBase
		  ,SUM(ISNULL(sp.LicenseeJackpot,0) * ex.Rate) 				   AS LicenseeJackpotBase
		  ,SUM(ISNULL(sp.LicenseePromotion,0) * ex.Rate) 			   AS LicenseePromotionBase
		  ,SUM(ISNULL(sp.FinalLicensingFee,0) * ex.Rate) 			   AS LicenseeTotalBase
	FROM bodb_LicenseeReport.dbo.SabaPlayPerformance sp WITH (NOLOCK)
		INNER JOIN @tmp_Product p ON sp.ProductID = p.ProductID
	CROSS APPLY
	(	SELECT TOP 1  e.CurrencyCode, e.Rate
		FROM #Exchange e 
		WHERE sp.RptDate = e.ExchangeDate 
		  AND CASE WHEN sp.CurrencyCode = 'USDT' THEN 'USD' ELSE sp.CurrencyCode END  = e.CurrencyCode
		  AND e.ExchangeId =  CASE WHEN sp.CurrencyCode = 'VND' THEN 51
								   WHEN sp.CurrencyCode = 'INR' THEN 61
								   WHEN sp.CurrencyCode = 'COP' THEN 84 
								   WHEN sp.CurrencyCode = 'JPY' THEN 32 
								   WHEN sp.CurrencyCode = 'LBP' THEN 217 
								   WHEN sp.CurrencyCode = 'TZS' THEN 135 
								   WHEN sp.CurrencyCode = 'KRW' THEN 45
							  ELSE e.ExchangeId END
	) ex
	OUTER APPLY(
		SELECT d.DiscountGroupId, d.rate
		FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupDetail d WITH (NOLOCK) ON d.DiscountGroupId = h.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = h.DiscountGroupId
		WHERE h.DiscountGroupType = 23
		  AND a.PartyID = @PartyId
		  AND p.ProductId = sp.ProductID
		  AND h.FromDate <= @TDate
		  AND h.ToDate >= @TDate
	) AS ds
	WHERE sp.DataType = 2 AND sp.RptDate = @TDate AND SiteID = @OperatorID AND Environment = @Environment
	GROUP BY sp.CurrencyCode, ex.Rate, sp.ProductID, sp.ProductName, sp.LicenseeChargeRate, ISNULL(ds.rate, 0)
	ORDER BY sp.ProductID, sp.ProductName, sp.LicenseeChargeRate, sp.CurrencyCode

	DECLARE @tmp_currencyList TABLE (CurrencyCode VARCHAR(12))
	INSERT INTO @tmp_currencyList (CurrencyCode)
	SELECT DISTINCT sp.CurrencyCode 		 
	FROM bodb_LicenseeReport.dbo.SabaPlayPerformance sp WITH (NOLOCK)
		INNER JOIN @tmp_Product p ON sp.ProductID = p.ProductID
	WHERE sp.DataType = 2 AND sp.RptDate = @TDate AND SiteID = @OperatorID AND Environment = @Environment


	IF @CurrencyRatio IS NOT NULL AND @CurrencyRatio <> '' AND EXISTS (SELECT TOP 1 1 FROM @tmp_currencyList)
	BEGIN
		BEGIN TRY
			; WITH t AS
			(
				SELECT 
					CAST (TRIM(r.[key]) AS VARCHAR(12)) AS Currency,
					TRIM(x2.Code) Code, 
					TRIM(x2.rate) rate
				FROM OPENJSON(@CurrencyRatio, '$') AS r
				CROSS APPLY (
					SELECT x1.Code, x1.rate FROM  STRING_SPLIT( r.[value] ,';') x
					CROSS APPLY (
						SELECT  LTRIM(RTRIM(SUBSTRING(TRIM(value), 1, CHARINDEX('=', TRIM(value)) - 1))) AS Code,
								LTRIM(RTRIM(SUBSTRING(TRIM(value), CHARINDEX('=',TRIM(value)) + 1, LEN(TRIM(value))))) AS rate
					) x1
				) x2
			), u AS
			(
				select t.*, x1.* from t
				CROSS APPLY (
						SELECT  LTRIM(RTRIM(SUBSTRING(TRIM(t.rate), 1, CHARINDEX(':', TRIM(t.rate)) - 1))) AS r1,
								LTRIM(RTRIM(SUBSTRING(TRIM(t.rate), CHARINDEX(':',TRIM(t.rate)) + 1, LEN(TRIM(t.rate))))) AS r2
					) x1
			)

			,u1 AS
			   (select u.Currency, u.Code, CAST(x.r1_d AS MONEY) / CAST(u.r1 AS MONEY) AS r1_n,  CAST(x.r2_d AS MONEY) / CAST(u.r2  AS MONEY) AS r2_n,
					   CASE WHEN  CAST(x.r1_d AS MONEY) / CAST(u.r1 AS MONEY) < 1. THEN CAST ( 1. / (CAST(x.r1_d AS MONEY) / CAST(u.r1 AS MONEY)) AS MONEY)
							WHEN  CAST(x.r2_d AS MONEY) / CAST(u.r2  AS MONEY) < 1. THEN  CAST ( 1. / (CAST(x.r2_d AS MONEY) / CAST(u.r2 AS MONEY)) AS MONEY)
							ELSE 1 END multiply
	
			  from u
			  CROSS APPLY (
				SELECT TOP 1 u1.r2 AS r2_d, u1.r1 AS r1_d FROM u u1 WHERE u.Currency = u1.Currency AND u1.Currency = u1.Code
			  ) x
			 ), u2 AS
			 (
				SELECT Currency, Code, CAST (r1_n * multiply AS INT ) r1_n, CAST (r2_n * multiply AS INT ) r2_n
				FROM u1
			 )

			 SELECT @RatioNote =   '[' + STRING_AGG(note,',') + ']'
			 FROM
			 (
				SELECT  '"' + u_c.Currency + ' => ' + STRING_AGG( u_c.Code + ' = ' + CAST(r1_n AS VARCHAR(20)) + ':' + CAST(r2_n AS VARCHAR(20))  , ' ; ')  + '"' AS note  
				FROM u2 u_c 
				WHERE u_c.Currency COLLATE SQL_Latin1_General_CP1_CI_AS   IN (SELECT m.CurrencyCode COLLATE SQL_Latin1_General_CP1_CI_AS FROM @tmp_currencyList m)
				GROUP BY u_c.Currency
			 ) x
		END TRY
		BEGIN CATCH
			SELECT @RatioNote = NULL
		END CATCH

	END

END
GO
