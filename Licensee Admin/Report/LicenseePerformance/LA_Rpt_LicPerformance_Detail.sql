/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE dbo.LA_Rpt_LicPerformance_Detail
	@PartyIDs VARCHAR(4000) = ''
	, @Currency INT = 0
	, @FromDate SMALLDATETIME
	, @ToDate SMALLDATETIME
	, @ProductCodes VARCHAR(500)
	, @IsConvert BIT = 0
	, @BaseCurrency INT = 12
	, @BaseCurrencyName VARCHAR(10) = 'GBP'
	, @DrawFilter SMALLINT = 1
AS
/*	Created: 20141209@Patrick
	Task: LicenseeAdmin - Get Licensee Performance Detail report
	DB: DB052.bodb02

	Revisions:
		- 20150806@Florent: add column SB launch date to output
		- 20150814@Florent: add "*" on licensee name when pay minfee
		- 20151209@Bravo:	Enhance view data as billing invoice - re-write sp call data from table rpt_BettingByProduct
		- 20160128@Bruce: Fixbug:
					+ There is no minimum fee when data display individual currency
					+ Exclude Reject , Void, Refund
					+ Include other products
					+ LaunchDate = MIN(FromDate) of all charge types/products
					+ Convert Minfee currency
		- 20160202@Bruce: Add BA Commission and Amount due to BA
		- 20160608@Bruce: Fixbug:
					+ Fix credit licensees name
					+ Wrong data of credit licensee
					+ fix minfee amount when select single licensee in minfee group
		- 20161024@Scofield: 
					+ Calculate Discount for HAIFA (discount group type: 3)
					+ Fix minfee bug for case no ticket data
		- 20170412: @Scofield - Removing Trading Bet Types [#73310]
		- 20170830@Scofield: Rebate/ add more products for Licensee performance in details report[#80796]
		- 20171205@Bruce: fix partyid length [#87723]
		- 20182501@Bruce: Include exchange winloss [#87754]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180703@Parsons: Integrate Pragmatic Win Loss [#94108]
		- 20180712@Bruce: Enhance Manage Discount group [#94282]
		- 20180718@Bruce: use decimal to void margin not match among reports [#94108]
		- 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
		- 20180924@Parsons: LA - LPID report - Apply one discount rate across all base currencies [#100046]
		- 20181122@Scofield: Integrate Bidme games (GD product) [#103695]
	    - 20190325@Parsons: Integrate-PP-Promotion-Prize [#109014]
		- 20190718@Bruce: Integrate CN88 data in LA [#116859]	
		- 20191021@Parsons: Non-peak hour promotion [#119538]    

	Param's Explanation:  
	  + @PartyIDs : a string of list LicenseeID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @ProductCode : string,

	  + @IsConvert: =1 : convert figure to
					=0 : no convert 
					(datatype:bit)
	  + @BaseCurrency /  @BaseCurrencyName
					6 : convert to EUR
					 2: convert to MYR
					 3: convert to USD
					 12: convert to GBP
					 13: convert to CNY
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @GD_Tip SMALLINT = 1706
	DECLARE @BAProductId INT = 3, @ExchangeProductId INT = 31, @PragmaticProductId INT = 32 

	-- *********************************************************************************************************
	-- *** Calculate Previous FromDate, Previous ToDate from FromDate, ToDate
	-- *** Previous FromDate = FromDate - 1 Month, Previous ToDate = ToDate - 1 Month
	-- *** For special cases:
	-- *** 		- FromDate, ToDate: 20170315, 20170330 --> PreviousFromDate, PreviousToDate: 20170215, 20170228
	-- *** 		- FromDate, ToDate: 20170330, 20170330 --> PreviousFromDate, PreviousToDate: 20170228, 20170228
	-- *********************************************************************************************************
	-- Region: get period date	
	DECLARE @PrevFromDate DATE, @PrevToDate DATE
	SELECT @PrevFromDate = DATEADD(M, -1,  @FromDate)
		, @PrevToDate = CASE WHEN DATEDIFF(D, @ToDate, DATEADD(S, - 1, DATEADD(MM, DATEDIFF(M, 0, @ToDate) + 1, 0))) = 0
						THEN DATEADD(S, - 1, DATEADD(MM, DATEDIFF(M, 0, @ToDate), 0))
						ELSE DATEADD(MM, - 1, @ToDate) END
	-- End region

	-- ******************************************************************* 
	-- *** Split @PartyIDs to @PartyIdTable
	-- *** Example: 
	-- *** 		- @PartyIDs = "14,21" --> @PartyIdTable (14, 1), (21, 1)
	-- *******************************************************************
	-- Region: Split party id	
	DECLARE @PartyIdTable TABLE (PartyId INT, IsSelected BIT)
	INSERT INTO @PartyIdTable
	SELECT val, 1 FROM bodb02.dbo.Lrf_f_StringSplit(@PartyIDs, ',')
	-- End region

	-- ************************************************************************
	-- *** Select all PartyGroupId, PartyId 
	-- *** From LA_PartyGroupAssignment 
	-- *** Where PartyGroupId has relationship with PartyIds in (PartyIdTable)
	-- ************************************************************************
	-- Party groups
	-- select all parties in the same group	
	DECLARE @PartyGroup AS TABLE (PartyGroupId INT, PartyId INT, IsSelected BIT)
	INSERT	INTO @PartyGroup(PartyGroupId, PartyId)
	(
		SELECT	PartyGroupId, PartyId
		FROM	bodb_licensee.dbo.LA_PartyGroupAssignment WITH(NOLOCK)
		WHERE PartyGroupId IN (
			SELECT DISTINCT p1.PartyGroupId  
			FROM bodb_licensee.dbo.LA_PartyGroupAssignment p1 WITH(NOLOCK)
			INNER JOIN @PartyIdTable p2 ON p1.PartyId=p2.PartyId  
		)
	)

	-- ***********************************************************************************
	-- *** Update @PartyIdTable, PartyIds with PartyId from @PartyGroup
	-- *** It means: Get all Parties which have relationship with @PartyIds params
	-- ***********************************************************************************
	-- insert parties in same group to party table so we can refere when calculate minfee	
	INSERT INTO @PartyIdTable
	SELECT PartyId, 0 FROM @PartyGroup WHERE PartyId NOT IN (SELECT p2.PartyId FROM @PartyIdTable p2)

	SET @PartyIds = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM @PartyIdTable FOR XML PATH(''))
	-- End region

	-- ***********************************************************
	-- *** Get AffectedDate for all Parties in (PartyIdTable)
	-- *** AffectedDate = Min(FromDate) from table OAS_ChargeInfo
	-- ***********************************************************
	-- Region: Effective data
	DECLARE @tmpPartySBLaunchDate AS TABLE (PartyID INT, AffectedDate SMALLDATETIME)
	;WITH P(FromDate,FromParty) AS (
		SELECT ci.FromDate, ci.FromParty
		FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map WITH (NOLOCK) ON map.ChargeID = ci.ChargeID and map.SystemID = 2  
		WHERE ci.FromParty IN (SELECT PartyId FROM @PartyIdTable) AND  
				ci.ProductId NOT IN (SELECT DISTINCT ProductId FROM bodb_licensee.dbo.LA_Product3rdSub WITH (NOLOCK))  
		UNION ALL  
		SELECT s.FromDate, ci.FromParty  
		FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)  
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty  
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map WITH (NOLOCK) ON map.ChargeID = ci.ChargeID and map.SystemID = 2  
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfoSub s WITH (NOLOCK) ON s.ChargeIDRef = ci.ChargeID AND s.FromParty = ci.FromParty  
		WHERE ci.FromParty IN (SELECT PartyId FROM @PartyIdTable)  
	)
	INSERT INTO @tmpPartySBLaunchDate(AffectedDate,PartyID)
	SELECT MIN(FromDate), FromParty FROM P GROUP BY FromParty
	-- End region

	-- Region: Party charge info
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		DECIMAL(7,5),
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			Bettype		INT)

	-- ***********************************************************************************************
	-- *** Get ChargeInfo for @PartyIDs in 2 period: FromDate-ToDate, PreviousFromDate-PreviousToDate
	-- ***********************************************************************************************
	-- select bettype to avoid duplicated data of MGC
	DECLARE @CreditLicensees AS TABLE(PartyId INT)
	INSERT INTO @CreditLicensees SELECT PartyId FROM bodb_licensee.dbo.OAS_PartyDetail WITH(NOLOCK) WHERE IsDeposit = 0
	
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, 
				CASE WHEN ISNULL(ci.isDeposit, 0) = 1 THEN ci.DI_Rate ELSE 0 END,
				ci.Fromdate,
				ci.ToDate,
				CASE WHEN ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END
		FROM	bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, @ProductCodes) ci
		LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	((ci.PartyID IN (SELECT cl.PartyId FROM @CreditLicensees cl) AND DI_Rate = 0) OR DI_Rate > 0)
			AND ProductId <> 1 --exclude RB
			AND ChargeType <> 12 -- exclude Gd tip
	)
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, 
				CASE WHEN ISNULL(ci.isDeposit, 0) = 1 THEN ci.DI_Rate ELSE 0 END,
				ci.Fromdate,
				ci.ToDate,
				CASE WHEN ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END
		FROM	bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIDs, @PrevFromDate, @PrevToDate, @ProductCodes) ci
		LEFT JOIN bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	((ci.PartyID IN (SELECT cl.PartyId FROM @CreditLicensees cl) AND DI_Rate = 0) OR DI_Rate > 0)
			AND ProductId <> 1 --exclude RB
			AND ChargeType <> 12 -- exclude Gd tip
	)
	-- End region	

	-- this table hold data from sp: LA_AmountToCompanySel
	CREATE TABLE #AmountToCompany (
		PartyId			INT,
		ProductId		INT,
		Fee				MONEY,
		Discount		MONEY,
		Rebate			MONEY,
		IsChargedByMinFee	BIT,
		IsCurrent			BIT
	)
	IF(@IsConvert = 0)
	BEGIN
		SELECT @BaseCurrencyName = e.Code, @BaseCurrency = @Currency FROM bodb02.dbo.Exchange e WITH (NOLOCK) WHERE e.exchangeid = @Currency
	END

	--  Minimum fee is calculated for all currencies that licensee offer. There is no minimum fee when data display individual currency.
		-- current month
		INSERT INTO #AmountToCompany(PartyId,ProductId,Fee,Discount,Rebate,IsChargedByMinFee)
		EXEC bodb_licensee.dbo.LA_AmountToCompanyByDiscountCurrencySel @FromDate,@ToDate,@PartyIds,@ProductCodes,@BaseCurrencyName,@BaseCurrency,@Currency

		UPDATE #AmountToCompany SET IsCurrent = 1

		-- previous month
		INSERT INTO #AmountToCompany(PartyId,ProductId,Fee,Discount,Rebate,IsChargedByMinFee)
		EXEC bodb_licensee.dbo.LA_AmountToCompanyByDiscountCurrencySel @PrevFromDate, @PrevToDate,@PartyIds,@ProductCodes,@BaseCurrencyName,@BaseCurrency,@Currency

		UPDATE #AmountToCompany SET IsCurrent = 0 WHERE IsCurrent IS NULL
	-- End region

	-- **********************************************************************************************
	-- *** Get Exchange info for @BaseCurrencyName in 2 periods (current period and previous period)
	-- **********************************************************************************************
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange (
			ExchangeDate	DATE,
			ExchangeID		INT,
			CurrencyCode	VARCHAR(10),
			Rate			FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@PrevFromDate, @PrevToDate, @BaseCurrencyName)

	CREATE NONCLUSTERED INDEX Idx_Exchange ON #Exchange (ExchangeDate, ExchangeID)

	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END
	-- End region

	-- Region: Get Amount by Product
	CREATE	TABLE #TempData (
			LicenseeId		INT,
			PartyId			INT,
			rptDate			DATETIME,
			CurrencyId		INT,
			BetCount		INT,
			Turnover		MONEY,
			WinLoss			MONEY,
			AComm			MONEY,
			PComm			MONEY,
			ProductId		TINYINT,
			AmountToCompany MONEY,
			IsApplyMinFee	BIT)

	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,BetCount,Turnover,WinLoss,AComm,PComm,ProductId,AmountToCompany)
	(
		SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(CASE WHEN (@DrawFilter = 2 AND b.StatusId = 111) OR b.Bettype=@GD_Tip THEN 0 ELSE b.BetCount END),
				SUM(b.Turnover * CASE WHEN @DrawFilter IN (2, 3) 
										THEN CASE	WHEN b.StatusId = 111 THEN 0
													WHEN b.StatusId IN (114, 115) THEN 0.5
											 ELSE 1 END
										ELSE 1 END) * e.Rate,
				SUM(CASE WHEN b.Bettype=@GD_Tip THEN 0 ELSE b.MemberWL END) * e.Rate,
				SUM(ISNULL(b.CommissionA, 0)) * e.Rate,
				SUM(ISNULL(b.CommissionP, 0)) * e.Rate,
				p.ProductId,
				SUM((CASE WHEN b.Bettype=@GD_Tip THEN 0 ELSE -b.MemberWL END * p.Rate) - (CASE 
					WHEN b.ProductId = @BAProductId THEN ISNULL(b.CommissionA, 0)
					WHEN b.ProductID = @ExchangeProductId THEN ISNULL(b.CommissionA, 0) + ISNULL(b.CommissionP, 0)
					ELSE 0 END)) * e.Rate
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate OR b.rptDate BETWEEN @PrevFromDate AND @PrevToDate)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund 
				AND (@Currency = 0 OR b.CurrencyID = @Currency)
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, e.Rate
	)

	-- insert zero winloss for case: product don't have any ticket
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,BetCount,Turnover,WinLoss,AComm,PComm,ProductId,AmountToCompany)
	SELECT LicenseeId, PartyId, FromDate, @BaseCurrency,0,0,0,0,0,ProductID,0
	FROM @PartyChargeInfo

	-- Sum products
	BEGIN
		DECLARE @SumByProducts TABLE(
			PartyId			INT,
			BetCount		INT,
			Turnover		MONEY,
			WinLoss			MONEY,
			AComm			MONEY,
			PComm			MONEY,
			AmountToCompany	MONEY,
			ProductId		INT,
			IsCurrent		BIT,
			HasMinFee		BIT,
			Discount		MONEY,
			Rebate			MONEY
		)
		
		-- sum by product
		INSERT INTO @SumByProducts (PartyId,ProductId,IsCurrent,BetCount,Turnover,WinLoss,AComm,PComm,AmountToCompany,HasMinFee)
		SELECT	PartyId
				,ProductId
				,(CASE WHEN MONTH(rptDate) = MONTH(@FromDate) THEN 1 ELSE 0 END) IsCurrent
				,SUM(BetCount) BetCount
				,SUM(Turnover) Turnover
				,SUM(WinLoss) WinLoss
				,SUM(AComm) AComm
				,SUM(PComm) PComm
				,SUM(AmountToCompany) AmountToCompany
				,0 HasMinFee
		FROM #TempData
		GROUP BY PartyId, ProductId, CASE WHEN MONTH(rptDate) = MONTH(@FromDate) THEN 1 ELSE 0 END

		-- apply minfee
		UPDATE s SET 
			AmountToCompany = m.Fee,
			HasMinFee = m.IsChargedByMinFee,
			Discount = m.Discount,
			Rebate = m.Rebate
		FROM @SumByProducts s
		INNER JOIN #AmountToCompany m ON m.PartyId = s.PartyId AND m.IsCurrent = s.IsCurrent AND m.ProductId = s.ProductId
	END

	-- Region: Result
	CREATE TABLE #Result (
		PartyId				INT,
		ProductId			INT,
		PartyName			VARCHAR(100),
		LaunchDate			DATE,
		BetCount			INT,
		AverageBet			MONEY,
		Turnover			MONEY,
		WinLoss				MONEY,
		BACommission		MONEY,
		AmountToBA			MONEY,
		Margin				MONEY,
		SportsbookFee		MONEY,
		OthersFee			MONEY,
		SportbookDiscount	MONEY,
		OthersDiscount		MONEY,
		SportbookRebate		MONEY,
		OthersRebate		MONEY,
		PromotionSportsbook	MONEY,
		TotalFee			MONEY,
		NegativeAmount		MONEY,
		IsCurrent			BIT
	)

	-- ************************************
	-- *** Calculate #Result for SportBook
	-- ************************************
	INSERT INTO #Result (PartyId, ProductId, PartyName, SportsbookFee, IsCurrent, BetCount, AverageBet, Turnover, WinLoss, Margin, OthersFee, SportbookDiscount, BACommission, SportbookRebate)
	SELECT	p.PartyId,
			s.ProductId,
			(CASE op.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE op.PartyName END) + (CASE WHEN s.HasMinFee = 1 AND s.AmountToCompany != 0 THEN ' *' ELSE '' END),
			s.AmountToCompany,
			s.IsCurrent,
			s.BetCount,
			0 AS AverageBet,
			s.Turnover,
			s.WinLoss,
			0 AS Margin,
			0 AS OthersFee,
			s.Discount,
			0 AS BACommission,
			s.Rebate
	FROM	@PartyIdTable p
			INNER JOIN bodb_licensee.dbo.OAS_Party (NOLOCK) op ON p.PartyId = op.PartyID
			INNER JOIN @SumByProducts s ON p.PartyId = s.PartyId
	WHERE	s.ProductId = 0

	/*Update Promotion column*/
	IF(EXISTS(SELECT val FROM bodb02.dbo.strSplit(@ProductCodes, ',') WHERE val = 'SB'))
	BEGIN
		;WITH cte_Promotion AS(
			SELECT pc.PartyId, r.SiteID,(CASE WHEN MONTH(rptDate) = MONTH(@FromDate) THEN 1 ELSE 0 END) IsCurrent, SUM(r.RedemptionPrize * cExchange.Rate) AS Prize
			FROM bodb_LicenseeReport.dbo.rptLicPromotion r WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT PartyId, LicenseeId FROM @PartyChargeInfo WHERE ProductID = 0) pc ON r.SiteID = pc.LicenseeId
				INNER JOIN #Exchange cExchange ON r.RptDate = cExchange.ExchangeDate AND r.CurrencyID = cExchange.ExchangeID
				WHERE (r.RptDate BETWEEN @FromDate AND @ToDate) OR (r.RptDate BETWEEN @PrevFromDate AND @PrevToDate)
				GROUP BY pc.PartyId, r.SiteID, (CASE WHEN MONTH(rptDate) = MONTH(@FromDate) THEN 1 ELSE 0 END)
		)
		UPDATE r
		SET PromotionSportsbook = p.Prize
		FROM #Result r
			INNER JOIN cte_Promotion p ON r.PartyId = p.PartyId AND r.IsCurrent = p.IsCurrent
	END

	-- ********************************************************
	-- *** Calculate Other (!= SportBook) and Merge to #Result
	-- ********************************************************
	-- 31 exchange: include negative amount
	;WITH sumOther AS (
		SELECT t.IsCurrent, t.PartyId,
			SUM(t.BetCount)		AS BetCount,
			SUM(t.Turnover)		AS Turnover,
			SUM(ISNULL(t.Discount,0))	AS Discount,
			SUM(ISNULL(t.Rebate,0))		AS Rebate,
			SUM(CASE WHEN t.ProductId = @ExchangeProductId THEN t.PComm ELSE 0 END + t.WinLoss)							AS WinLoss,
			SUM(CASE WHEN t.ProductId = @BAProductId THEN t.AComm ELSE 0 END)											AS BAComm,
			SUM(CASE WHEN t.ProductId = @BAProductId THEN t.AmountToCompany ELSE 0 END)									AS AmountToBA,
			SUM(CASE WHEN t.ProductId = @ExchangeProductId OR (t.ProductId = @PragmaticProductId AND t.AmountToCompany < 0) THEN t.AmountToCompany ELSE 0 END)	AS NegativeAmount,
			SUM(CASE WHEN t.ProductId IN(@BAProductId, @ExchangeProductId) OR t.AmountToCompany < 0 THEN 0 ELSE t.AmountToCompany END) AmountToCompany
		FROM @SumByProducts t
		WHERE t.ProductId != 0
		GROUP BY t.IsCurrent, t.PartyId
	)
	MERGE #Result r
	USING sumOther s ON r.PartyId = s.PartyId AND r.IsCurrent = s.IsCurrent
	WHEN MATCHED THEN 
		UPDATE SET 
			r.OthersFee = s.AmountToCompany
			,r.BACommission = s.BAComm
			,r.AmountToBA = s.AmountToBA
			,r.OthersDiscount = ISNULL(s.Discount,0)
			,r.OthersRebate = ISNULL(s.Rebate,0)
			,r.BetCount = ISNULL(r.BetCount,0) + ISNULL(s.BetCount,0)
			,r.Turnover = ISNULL(r.Turnover,0) + ISNULL(s.Turnover,0)
			,r.WinLoss = ISNULL(r.WinLoss,0) + ISNULL(s.WinLoss,0)
			,r.NegativeAmount = ISNULL(s.NegativeAmount,0)
	WHEN NOT MATCHED BY TARGET THEN 
		INSERT(PartyId, IsCurrent, BetCount, Turnover, WinLoss, BACommission, AmountToBA, OthersDiscount, OthersRebate,NegativeAmount,
			SportsbookFee,
			OthersFee)
		VALUES(s.PartyId, s.IsCurrent, s.BetCount, s.Turnover, s.WinLoss, s.BAComm, s.AmountToBA, s.Discount, s.Rebate,s.NegativeAmount,
			0,
			s.AmountToCompany
		);

	UPDATE	r
	SET	LaunchDate	= t.AffectedDate,
		PartyName	= ISNULL(r.PartyName,op.PartyName),
		AverageBet	= CASE WHEN r.BetCount = 0 THEN r.Turnover ELSE (CAST(r.Turnover AS DECIMAL(20,5)) / r.BetCount) END,
		Margin		= CASE WHEN r.Turnover = 0 THEN r.WinLoss ELSE (-CAST(r.WinLoss AS DECIMAL(20,5))/ r.Turnover) END,
		TotalFee	= ISNULL(r.SportsbookFee,0) + ISNULL(r.OthersFee,0) - ISNULL(r.SportbookDiscount,0) - ISNULL(r.OthersDiscount,0) - ISNULL(r.SportbookRebate,0) - ISNULL(r.OthersRebate,0) - ISNULL(r.PromotionSportsbook,0)
	FROM	#Result r
	INNER JOIN @tmpPartySBLaunchDate t ON t.PartyID = r.PartyId
	INNER JOIN bodb_licensee.dbo.OAS_Party (NOLOCK) op ON r.PartyId = op.PartyID
	-- End region

	-- Region: Select Data	
	SELECT	r.PartyId,
			(CASE r.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE r.PartyName END) AS PartyName,
			r.LaunchDate,
			r.BetCount																				AS TotalTrans,
			r.AverageBet																			AS AverageBetValue,
			ISNULL(r.Turnover,0)																	AS Turnover,
			ISNULL(p.Turnover,0)																	AS PreviousTurnover,
			ISNULL(r.WinLoss,0)																		AS GrossWinLoss,
			ISNULL(p.WinLoss,0)																		AS PreviousGrossWinLoss,
			ISNULL(r.Margin,0)																		AS Margin,
			ISNULL(p.Margin,0)																		AS PreviousMargin,
			CASE WHEN ISNULL(r.BACommission,0) > 0 THEN ISNULL(r.BACommission,0) ELSE 0 END			AS BACommission,		-- Negative number is displayed as 0
			CASE WHEN ISNULL(p.BACommission,0) > 0 THEN ISNULL(p.BACommission,0) ELSE 0 END			AS PreviousBACommission,
			ISNULL(r.AmountToBA, 0)																	AS AmountDueToBA,		-- Keep as it is
			ISNULL(p.AmountToBA, 0)																	AS PreviousAmountDueToBA,
			CASE WHEN r.SportsbookFee > 0 THEN r.SportsbookFee ELSE 0 END							AS SportsbookFee,
			CASE WHEN ISNULL(p.SportsbookFee,0) > 0 THEN p.SportsbookFee ELSE 0 END					AS PreviousSportsbookFee,
			ISNULL(r.OthersFee,0) + ISNULL(r.NegativeAmount,0)										AS OtherProductsFee,
			ISNULL(p.OthersFee,0) + ISNULL(p.NegativeAmount,0)										AS PreviousOtherProductsFee,
			CASE WHEN r.SportbookDiscount > 0 THEN r.SportbookDiscount ELSE 0 END					AS DiscountSportsbook,
			CASE WHEN ISNULL(p.SportbookDiscount,0) > 0 THEN p.SportbookDiscount ELSE 0 END			AS PreviousDiscountSportsbook,
			CASE WHEN r.OthersDiscount > 0 THEN r.OthersDiscount ELSE 0 END 						AS DiscountOthers,
			CASE WHEN ISNULL(p.OthersDiscount,0) > 0 THEN p.OthersDiscount ELSE 0 END				AS PreviousDiscountOthers,
			CASE WHEN r.SportbookRebate > 0 THEN r.SportbookRebate ELSE 0 END 						AS RebateSportsbook,
			CASE WHEN ISNULL(p.SportbookRebate,0) > 0 THEN p.SportbookRebate ELSE 0 END 			AS PreviousRebateSportsbook,
			CASE WHEN r.OthersRebate > 0 THEN r.OthersRebate ELSE 0 END 							AS RebateOthers,
			CASE WHEN ISNULL(p.OthersRebate,0) > 0 THEN p.OthersRebate ELSE 0 END 					AS PreviousRebateOthers,
			ISNULL(r.PromotionSportsbook, 0)														AS PromotionSportsbook,
			ISNULL(p.PromotionSportsbook, 0)														AS PreviousPromotionSportsbook,
			(CASE WHEN r.TotalFee > 0 THEN r.TotalFee ELSE 0 END) + ISNULL(r.NegativeAmount,0)		AS TotalLicensingFee,
			(CASE WHEN p.TotalFee > 0 THEN p.TotalFee ELSE 0 END) + ISNULL(p.NegativeAmount,0)		AS PreviousTotalLicensingFee
	FROM	#Result r
			LEFT JOIN (SELECT * FROM #Result WHERE IsCurrent = 0) p ON r.PartyId = p.PartyId
	WHERE	r.IsCurrent = 1 AND r.PartyId IN (SELECT pt.PartyId FROM @PartyIdTable pt WHERE IsSelected = 1)
		AND (r.BetCount > 0 OR r.SportsbookFee > 0)-- only show party has ticket, don't care previous month

	-- End region

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #Result
	DROP TABLE #AmountToCompany
	-- End region
END
GO