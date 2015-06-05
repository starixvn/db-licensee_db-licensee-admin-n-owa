USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_3rdPartyProductWinloss]    Script Date: 05/06/2015 09:50:08 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_3rdPartyProductWinloss] 
	  @PartyId				VARCHAR(500)
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @ProductCode			VARCHAR(6)
	, @CurrencyId			INT				= 0
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
	, @DrawFilter			SMALLINT		= 1
	, @ExcludeTest			BIT				= 0
WITH RECOMPILE
AS
/*  Created: 20150525@Florent		
	Task : Report - Third Party Product Winloss		
	DB: DB052.bodb02
	Revisions:  			
	Param's Explanation:  				
		+ @ProductCode:	+ 'GD'	Gold Deluxe
*/  
SET NOCOUNT ON
BEGIN			
	DECLARE @LicenseeID INT			
	CREATE TABLE #Result (
			PartyID			INT
			, ParentId		INT
			, Winlostdate	DATETIME
			, CurrencyId	INT
			, TurnOver		MONEY
			, Winlost		MONEY			
			, LicenseeWL	MONEY			
			, Company		MONEY
			, Amtdueto		MONEY
			, Betcount		BIGINT)
	DECLARE @tmpParty AS TABLE (
		PartyId				INT
		, ParentId			INT
		, LicenseeId		INT
		, ProductID			INT
		, Rate				MONEY
		, Rate3rd			MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)
	
	CREATE TABLE #Exchange( ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)
	CREATE TABLE #PartyList(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)
	
	INSERT INTO #PartyList
	EXEC bodb_licensee.dbo.LA_PartyListSel

	INSERT INTO @tmpParty(PartyId, ParentId, LicenseeId, ProductID, Rate,Rate3rd, Fromdate, Todate)
	(
		SELECT a.PartyID, p.ParentId, LicenseeID, a.ProductID, DI_Rate, b.Rate, a.Fromdate, a.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyID, @FromDate, @ToDate, @ProductCode, 'OA', @ExcludeTest) a
			LEFT JOIN #PartyList p ON a.PartyID = p.PartyId
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo b WITH (NOLOCK) ON p.ParentId = b.FromParty AND a.ProductID = b.ProductID AND (a.Fromdate BETWEEN b.FromDate AND b.ToDate OR a.Todate BETWEEN b.FromDate AND b.ToDate )		
	)	
	
	DECLARE @Recommend VARCHAR(MAX) = '', @SQL VARCHAR(8000) = ''
	CREATE TABLE #DataWinloss3rd (Recommend	INT, Winlostdate DATETIME, SportType INT, Currency INT, TurnOver MONEY, TotalTrans INT, Winloss MONEY)
	DECLARE @TempAG AS TABLE( LicenseeeID INT, CustId INT, CurrencyId INT)
	
	-- Product <> BA		
	IF (CHARINDEX('GD', @ProductCode) <> 0)-- GD
	BEGIN		
		--get licensee recommend			
		INSERT INTO @TempAG(LicenseeeID, CustId, CurrencyId)
		SELECT DISTINCT LicenseeID, CustID, Currency
		FROM bodb_licensee.dbo.f_SelLicenseeCust(@LicenseeID)
		WHERE (@CurrencyId = 0 OR (@CurrencyId <> 0 AND Currency = @CurrencyId))	
			AND (@ExcludeTest = 0 OR (@ExcludeTest <> 0 AND Currency <> 20))	
			AND LicenseeID IN (SELECT LicenseeId FROM @tmpParty)

		SELECT @Recommend = @Recommend + CAST(CustID AS VARCHAR) + ',' 
		FROM @TempAG 

		--truncate last comma
		SET @Recommend = SUBSTRING(@Recommend, 0, LEN(@Recommend))	

		IF LEN(@Recommend) > 8000
			SET @Recommend = ''

		INSERT INTO #DataWinloss3rd(Recommend, Winlostdate, Currency, TurnOver, TotalTrans, Winloss)
		EXECUTE dbo.LA_Rpt_ThirdPartyProductWinloss
				@ProductCodes	= @ProductCode
				, @Recommend	= @Recommend
				, @Currency 	= @CurrencyId
				, @DrawFilter	= @DrawFilter
				, @FromDate 	= @FromDate
				, @ToDate 		= @ToDate
		INSERT INTO #Result(PartyID, ParentId, Winlostdate, CurrencyId, Turnover, Winlost, LicenseeWL, Company, Amtdueto, Betcount)
		(
			SELECT   			  
				p.PartyId
				, p.ParentId 
				, b.Winlostdate     
				, CurrencyID		   
				, SUM(Turnover) AS Turnover
				, SUM(WinLoss) AS Winlost		
				, - SUM(Winloss) AS LicenseeWL								
				, - SUM(WinLoss * p.Rate) AS Company 
				, - SUM(WinLoss * p.Rate3rd) AS Amtdueto 
				, SUM(b.TotalTrans) AS BetCount	  
			FROM #DataWinloss3rd b WITH (NOLOCK)	
				INNER JOIN @TempAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId								
				INNER JOIN @tmpParty p ON ag.LicenseeeID = p.LicenseeId
			WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate				
			GROUP BY b.Winlostdate, CurrencyID , p.PartyId, p.ParentId
		)			
	END		
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	SELECT   														   
		d.ParentId					AS ParentId
		, pp.PartyName				AS ParentName
		, d.PartyID					AS PartyID
		, p.PartyName				AS PartyName
		, SUM(Betcount)				AS Betcount
		--orginal
		, SUM(TurnOver)				AS Turnover
		, SUM(Winlost)				AS MemberWinLoss		
		, SUM(LicenseeWL)			AS LicenseeWL		
		, CASE WHEN SUM(d.Company) < 0 THEN 0
			ELSE SUM(d.Company)
			END 					AS Company		
		, SUM(Amtdueto)				AS Amtdueto		
		
		--Base on currency
		, SUM(TurnOver * e.Rate)	AS TurnoverBase
		, SUM(Winlost * e.Rate)		AS MemberWinLossBase	
		, SUM(LicenseeWL * e.Rate)	AS LicenseeWLBase		
		, CASE WHEN SUM(d.Company * e.Rate) < 0 THEN 0
			ELSE SUM(d.Company * e.Rate)
			END					AS CompanyBase		
		, SUM(Amtdueto * e.Rate)	AS AmtduetoBase
	FROM													  
		#Result d  									  
		INNER JOIN #Exchange e ON d.Winlostdate = e.ExchangeDate AND d.CurrencyId = e.ExchangeId
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.OAS_Party pp WITH (NOLOCK) ON d.ParentId = pp.PartyID
	GROUP BY d.ParentId
		, pp.PartyName
		, d.PartyID		
		, p.PartyName	
	ORDER BY pp.PartyName ASC

	DROP TABLE #Exchange												   
	DROP TABLE #Result	
	DROP TABLE #DataWinloss3rd
	DROP TABLE #PartyList
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_3rdPartyProductWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_3rdPartyProductWinloss] TO bodbAdminNet