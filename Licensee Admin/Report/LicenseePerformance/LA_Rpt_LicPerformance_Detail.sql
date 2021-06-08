/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE dbo.LA_Rpt_LicPerformance_Detail
	@PartyIDs		VARCHAR(4000) = ''
	, @Currency		INT = 0
	, @FromDate		SMALLDATETIME
	, @ToDate		SMALLDATETIME
	, @ProductCodes VARCHAR(500)
	, @IsConvert	BIT = 0
	, @BaseCurrency INT = 12
	, @BaseCurrencyName VARCHAR(10) = 'GBP'
	, @DrawFilter	SMALLINT = 1
	, @LicenseePaying INT = 0
	, @PreviousPeriodType INT = 1
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
		- 20191125@Mason: Setup billing terms by Currency  [#120005]
	    - 20191205@Parsons: PP tournament [#123958]
	    - 20200409@Parsons: Integrate SA Gaming [#129276]
	    - 20200605@Parsons: Get Full Data For Licensee Groups [#135452]
		- 20200609@Parsons: Special handling for INH market [#128570] 
		- 20200624@Parsons: Keep Negative Licensing Fee for 2 special licensees 9wickets, 9Wsports [#136334]
		- 20200813@Parsons: Implement Group Min Fee [#134492]
	    - 20200821@Parsons: Implement PP JP Changes In Reports Phase 2 [#139055]
	    - 20200828@Parsons: Provide data of "this month last year" [#136417] 
		- 20200910@Parsons: Implement PP JP for Credit [#138984]
		- 20201007@Parsons: Always show party row regardless of having data or not [#142970]
		- 20201027@Parsons: Arcadia Gaming - Add Bonus feature [#143597]
		- 20201209@Parsons: Saba.club - Offer Freebet tickets [#141423]
		- 20210206@Parsons: Saba.club - Integrate Slot Game [#147977]
		- 20210513@Percy: Apply function to get Joint Venture Party List - Keep negative licensee fee [RedmineID: #154992]
		- 20210306@Danny: AE Sexy - Support Lucky Draw [#152141]

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
	  + @LicenseePaying: =0 : All
					=1 : Normal fee 
					=2 : Minimum fee
					=3 : Group min fee 
	  + @PreviousPeriodType: = 1: Same month last year
	                         = 2: Last month
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @GD_Tip SMALLINT = 1706, @SAG_Tip SMALLINT = 3007
	DECLARE @BAProductId INT = 3, @ExchangeProductId INT = 31, @PragmaticProductId INT = 32, @ArcadiaGamingId INT = 34, @Saba_clubProductID INT = 42,
			@PP_Contribution SMALLINT = 4297,
			@PP_JackpotPrize SMALLINT = 4298,
			@PPTournament SMALLINT = 4299,
			@PromotionPrize SMALLINT = 4300,
			@ArcadiaGamingBonus SMALLINT = 1906,
			@SBC_Contribution SMALLINT = 1698,
			@SBC_JackpotPrize SMALLINT = 1699,
			@SXG_LuckyDraw SMALLINT = 3150

	-- *********************************************************************************************************
	-- *** Calculate Previous FromDate, Previous ToDate from FromDate, ToDate
	-- *** Previous FromDate = FromDate - 1 Month, Previous ToDate = ToDate - 1 Month
	-- *** For special cases:
	-- *** 		- FromDate, ToDate: 20170315, 20170330 --> PreviousFromDate, PreviousToDate: 20170215, 20170228
	-- *** 		- FromDate, ToDate: 20170330, 20170330 --> PreviousFromDate, PreviousToDate: 20170228, 20170228
	-- *** Previous month should display full month
	-- ***		- FromDate, ToDate: 20200601, 20200630 --> PreviousFromDate, PreviousToDate: 20200501, 20200531
	-- *********************************************************************************************************
	-- Region: get period date	
	DECLARE @PrevFromDate DATE = CASE WHEN @PreviousPeriodType = 1 THEN DATEADD(yy, -1,  @FromDate) ELSE DATEADD(MM, -1,  @FromDate) END 
	DECLARE @PrevToDate DATE
	
	DECLARE @FirstDateNextMonth DATETIME = DATEADD(MM, DATEDIFF(MM, -1, @ToDate), 0)
	DECLARE @LastDateInCurrentMonth DATETIME = DATEADD(SS, -1, @FirstDateNextMonth)
	DECLARE @IsSelectedFullDayOfMonth BIT = 0
	IF(DATEDIFF(DD, @ToDate, @LastDateInCurrentMonth) = 0)
	BEGIN
		SET @IsSelectedFullDayOfMonth = 1
	END

	IF(@PreviousPeriodType = 1) -- Same month last year
	BEGIN
		DECLARE @FirstDateOfNextMonthLastYear DATETIME = DATEADD(MM, DATEDIFF(MM, -1, @ToDate) - 12, 0)
		SET @PrevToDate = CASE WHEN @IsSelectedFullDayOfMonth = 1 THEN DATEADD(SS, -1, @FirstDateOfNextMonthLastYear) 
							   ELSE DATEADD(YY, - 1, @ToDate) 
						  END 
	END
	ELSE -- Last month
	BEGIN
		DECLARE @FirstDateCurrentMonth DATETIME = DATEADD(MM, DATEDIFF(MM, 0, @FromDate), 0)
		SET @PrevToDate = CASE WHEN @IsSelectedFullDayOfMonth = 1 THEN DATEADD(SS, -1, @FirstDateCurrentMonth)
							   ELSE DATEADD(MM, - 1, @ToDate) 
						  END
	END
	-- End region

	-- ******************************************************************* 
	-- *** Split @PartyIDs to @PartyIdTable
	-- *** Example: 
	-- *** 		- @PartyIDs = "14,21" --> @PartyIdTable (14, 1), (21, 1)
	-- *******************************************************************
	-- Region: Split party id	
	DECLARE @PartyIdTable TABLE (PartyId INT, IsSelected BIT)
	INSERT INTO @PartyIdTable
	SELECT val, 1 FROM Lrf_f_StringSplit(@PartyIDs, ',')
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
			ChargeId	INT,
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

	-- this table hold data from sp: LA_AmountToCompanyByDiscountCurrencySel
	CREATE TABLE #AmountToCompany (
		PartyId			INT,
		ProductId		INT,
		Fee				MONEY,
		Discount		MONEY,
		Rebate			MONEY,
		IsChargedByMinFee		BIT,
		IsChargedByGroupMinFee	BIT,
		IsCurrent			BIT
	)
	IF(@IsConvert = 0)
	BEGIN
		SELECT @BaseCurrencyName = e.Code, @BaseCurrency = @Currency FROM Exchange e WITH (NOLOCK) WHERE e.exchangeid = @Currency
	END

	--  Minimum fee is calculated for all currencies that licensee offer. There is no minimum fee when data display individual currency.
		-- current month
		INSERT INTO #AmountToCompany(PartyId,ProductId,Fee,Discount,Rebate,IsChargedByMinFee,IsChargedByGroupMinFee)
		EXEC bodb_licensee.dbo.LA_AmountToCompanyByDiscountCurrencySel @FromDate,@ToDate,@PartyIds,@ProductCodes,@BaseCurrencyName,@BaseCurrency,@Currency

		UPDATE #AmountToCompany SET IsCurrent = 1

		-- previous month
		INSERT INTO #AmountToCompany(PartyId,ProductId,Fee,Discount,Rebate,IsChargedByMinFee,IsChargedByGroupMinFee)
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
	FROM LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM LA_f_ExchangeDailySel(@PrevFromDate, @PrevToDate, @BaseCurrencyName)

	CREATE NONCLUSTERED INDEX Idx_Exchange ON #Exchange (ExchangeDate, ExchangeID)

	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END
	-- End region

	-- Region: Get Amount by Product
	CREATE	TABLE #TempData (
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
			IsApplyMinFee	BIT,
			ExtraAmount		MONEY)

	;WITH cte_DataSource AS
	(
	  SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				p.ProductId,
				SUM(CASE WHEN (@DrawFilter = 2 AND b.StatusId = 111) THEN 0 ELSE b.BetCount END) AS BetCount,
				SUM(b.Turnover * CASE WHEN @DrawFilter IN (2, 3) 
										THEN CASE	WHEN b.StatusId = 111 THEN 0
													WHEN b.StatusId IN (114, 115) THEN 0.5
											 ELSE 1 END
										ELSE 1 END) AS Turnover,
				SUM(b.MemberWL) AS WinLoss,
				SUM(ISNULL(b.CommissionA, 0)) AComm,
				SUM(ISNULL(b.CommissionP, 0)) PComm,
				SUM(-b.MemberWL * ISNULL(cr.Rate, p.Rate) - 
					(CASE  WHEN b.ProductId = @BAProductId THEN ISNULL(b.CommissionA, 0)
						   WHEN b.ProductID = @ExchangeProductId THEN ISNULL(b.CommissionA, 0) + ISNULL(b.CommissionP, 0)
					       ELSE 0
				     END)) AS AmountToCompany,
				0 AS ExtraAmount
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeID AND b.CurrencyId = cr.CurrencyID
				LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('','') eb ON b.Bettype = eb.BettypeID
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate OR b.rptDate BETWEEN @PrevFromDate AND @PrevToDate)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND eb.BettypeID IS NULL
				AND	ISNULL(b.TicketType, 0) <> 2 -- Free_Bets_TicketType
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund 
				AND (@Currency = 0 OR b.CurrencyID = @Currency)
		GROUP BY b.rptdate, b.SiteId, p.PartyId, b.CurrencyID, p.ProductId

		UNION ALL

		SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				p.ProductId,
				0 BetCount,
				0 Turnover,
				0 WinLoss,
				0 AComm,
				0 PComm,
				0 AmountToCompany,
				SUM(CASE WHEN b.Bettype IN (@PP_Contribution, @SBC_Contribution) THEN ISNULL(-b.GrossWL, 0)
						 WHEN b.Bettype IN (@PPTournament,@PromotionPrize,@PP_JackpotPrize,@ArcadiaGamingBonus,@SBC_JackpotPrize,@SXG_LuckyDraw) OR ISNULL(b.TicketType, 0) = 2 THEN ISNULL(-b.MemberWL, 0)
						 ELSE 0
					END) AS ExtraAmount
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeID AND b.CurrencyId = cr.CurrencyID
				LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('','') eb ON b.Bettype = eb.BettypeID
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate OR b.rptDate BETWEEN @PrevFromDate AND @PrevToDate)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND (ISNULL(b.TicketType, 0) = 2 OR eb.BettypeID IS NOT NULL)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund 
				AND (@Currency = 0 OR b.CurrencyID = @Currency)
		GROUP BY b.rptdate, b.SiteId, p.PartyId, b.CurrencyID, p.ProductId
	)

	INSERT INTO #TempData (PartyId,rptDate,CurrencyId,BetCount,Turnover,WinLoss,AComm,PComm,ProductId,AmountToCompany,ExtraAmount)
	(
		SELECT	b.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(BetCount)				AS BetCount,
				SUM(b.Turnover * e.Rate)	AS Turnover,
				SUM(WinLoss * e.Rate)		AS WinLoss,
				SUM(b.AComm * e.Rate)		AS AComm,
				SUM(b.PComm * e.Rate)		AS PComm,
				b.ProductId,
				SUM(AmountToCompany * e.Rate)	AS AmountToCompany,
				SUM(ExtraAmount * e.Rate)		AS ExtraAmount
		FROM	cte_DataSource b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		GROUP BY b.PartyId, b.rptdate, b.CurrencyID, b.ProductId
	)

	-- insert zero winloss for case: product don't have any ticket
	INSERT INTO #TempData (PartyId,rptDate,CurrencyId,BetCount,Turnover,WinLoss,AComm,PComm,ProductId,AmountToCompany)
	SELECT PartyId, FromDate, @BaseCurrency,0,0,0,0,0,ProductID,0
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
			IsChargedByMinFee	   BIT,
			IsChargedByGroupMinFee BIT,
			Discount		MONEY,
			Rebate			MONEY,
			ExtraAmount		MONEY
		)
		
		-- sum by product
		INSERT INTO @SumByProducts (PartyId,ProductId,IsCurrent,BetCount,Turnover,WinLoss,AComm,PComm,AmountToCompany,ExtraAmount,IsChargedByMinFee,IsChargedByGroupMinFee)
		SELECT	PartyId
				,ProductId
				,(CASE WHEN MONTH(rptDate) = MONTH(@FromDate) AND YEAR(rptDate) = YEAR(@FromDate) THEN 1 ELSE 0 END) IsCurrent
				,SUM(BetCount)
				,SUM(Turnover)
				,SUM(WinLoss)
				,SUM(AComm)
				,SUM(PComm)
				,SUM(AmountToCompany)
				,SUM(ExtraAmount)
				,0 IsChargedByMinFee
				,0 IsChargedByGroupMinFee
		FROM #TempData
		GROUP BY PartyId, ProductId, (CASE WHEN MONTH(rptDate) = MONTH(@FromDate) AND YEAR(rptDate) = YEAR(@FromDate) THEN 1 ELSE 0 END)

		-- apply minfee
		UPDATE s SET 
			AmountToCompany = CASE WHEN credit.PartyId IS NULL OR s.ProductId = 0 THEN m.Fee + ISNULL(ExtraAmount, 0) ELSE 0 END,
			IsChargedByMinFee = m.IsChargedByMinFee,
			IsChargedByGroupMinFee = m.IsChargedByGroupMinFee,
			Discount = m.Discount,
			Rebate = m.Rebate
		FROM @SumByProducts s
		INNER JOIN #AmountToCompany m ON m.PartyId = s.PartyId AND m.IsCurrent = s.IsCurrent AND m.ProductId = s.ProductId
		LEFT JOIN @CreditLicensees credit ON credit.PartyId = s.PartyId
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
		PromotionOthers		MONEY,
		TotalFee			MONEY,
		NegativeAmount		MONEY,
		IsCurrent			BIT,
		IsChargedByMinFee BIT,
		IsChargedByGroupMinFee BIT
	)

	-- ************************************
	-- *** Calculate #Result for SportBook
	-- ************************************
	INSERT INTO #Result (PartyId, ProductId, PartyName, SportsbookFee, IsCurrent, BetCount, AverageBet, Turnover, WinLoss, Margin, OthersFee, SportbookDiscount, BACommission, SportbookRebate, IsChargedByMinFee, IsChargedByGroupMinFee)
	SELECT	p.PartyId,
			s.ProductId,
			(CASE op.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE op.PartyName END) + (CASE WHEN s.IsChargedByMinFee = 1 AND s.AmountToCompany != 0 THEN ' *' ELSE '' END),
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
			s.Rebate,
			s.IsChargedByMinFee,
			s.IsChargedByGroupMinFee
	FROM	@PartyIdTable p
			INNER JOIN bodb_licensee.dbo.OAS_Party (NOLOCK) op ON p.PartyId = op.PartyID
			INNER JOIN @SumByProducts s ON p.PartyId = s.PartyId
	WHERE	s.ProductId = 0

	/*Update PromotionSportsbook column*/
	IF(EXISTS(SELECT TOP 1 1 FROM #Result))
	BEGIN
		;WITH cte_PromotionSportsbook AS(
			SELECT pc.PartyId, r.SiteID,(CASE WHEN MONTH(rptDate) = MONTH(@FromDate) AND YEAR(rptDate) = YEAR(@FromDate) THEN 1 ELSE 0 END) IsCurrent, SUM(r.MemberWL * cExchange.Rate) AS Prize
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT PartyId, LicenseeId FROM @PartyChargeInfo WHERE ProductID = 0) pc ON r.SiteID = pc.LicenseeId
				INNER JOIN #Exchange cExchange ON r.RptDate = cExchange.ExchangeDate AND r.CurrencyID = cExchange.ExchangeID
				WHERE ((r.RptDate BETWEEN @FromDate AND @ToDate) OR (r.RptDate BETWEEN @PrevFromDate AND @PrevToDate)) 
						AND r.ProductID = 37 -- Saba promotion
						AND (@Currency = 0 OR @Currency = r.CurrencyId)

				GROUP BY pc.PartyId, r.SiteID, (CASE WHEN MONTH(rptDate) = MONTH(@FromDate) AND YEAR(rptDate) = YEAR(@FromDate) THEN 1 ELSE 0 END)
		)
		UPDATE r
		SET PromotionSportsbook = p.Prize
		FROM #Result r
			INNER JOIN cte_PromotionSportsbook p ON r.PartyId = p.PartyId AND r.IsCurrent = p.IsCurrent
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
			SUM(CASE WHEN (jvp.PartyId IS NOT NULL AND t.ProductId <> @BAProductId) OR t.ProductId = @ExchangeProductId OR (t.ProductId IN (@PragmaticProductId, @ArcadiaGamingId, @Saba_clubProductID) AND t.AmountToCompany < 0) THEN t.AmountToCompany ELSE 0 END)	AS NegativeAmount,
			SUM(CASE WHEN jvp.PartyId IS NOT NULL OR t.ProductId IN (@BAProductId, @ExchangeProductId) OR t.AmountToCompany < 0 THEN 0 ELSE t.AmountToCompany END) AS AmountToCompany
		FROM @SumByProducts t
			LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() jvp ON t.PartyId = jvp.PartyId
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
		TotalFee	= ISNULL(r.SportsbookFee,0) + ISNULL(r.OthersFee,0) - ISNULL(r.SportbookDiscount,0) - ISNULL(r.OthersDiscount,0) - ISNULL(r.SportbookRebate,0) - ISNULL(r.OthersRebate,0)
	FROM	#Result r
	INNER JOIN @tmpPartySBLaunchDate t ON t.PartyID = r.PartyId
	INNER JOIN bodb_licensee.dbo.OAS_Party (NOLOCK) op ON r.PartyId = op.PartyID
	-- End region

	-- treat negative LicensingFee as 0, except Joint Venture Parties
	UPDATE r
	SET r.TotalFee = CASE WHEN r.TotalFee < 0 THEN 0 ELSE r.TotalFee END,
		r.SportsbookFee = CASE WHEN r.SportsbookFee < 0 THEN 0 ELSE r.SportsbookFee END
	FROM #Result r
		LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() jvp ON r.PartyId = jvp.PartyId
	WHERE jvp.PartyId IS NULL

	-- Region: Select Data
	;WITH cte_Result AS
	(
		SELECT	ISNULL(rLeft.PartyId, rRight.PartyId) AS PartyId,
			CASE ISNULL(rLeft.PartyName, rRight.PartyName) WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE ISNULL(rLeft.PartyName, rRight.PartyName) END AS PartyName,
			ISNULL(rLeft.LaunchDate, rRight.LaunchDate) AS LaunchDate,
			ISNULL(rLeft.BetCount,0)																	AS TotalTrans,
			ISNULL(rRight.BetCount,0)																	AS PreviousTotalTrans,
			ISNULL(rLeft.AverageBet,0)																	AS AverageBetValue,
			ISNULL(rLeft.Turnover,0)																	AS Turnover,
			ISNULL(rRight.Turnover,0)																	AS PreviousTurnover,
			ISNULL(rLeft.WinLoss,0)																		AS GrossWinLoss,
			ISNULL(rRight.WinLoss,0)																	AS PreviousGrossWinLoss,
			ISNULL(rLeft.Margin,0)																		AS Margin,
			ISNULL(rRight.Margin,0)																		AS PreviousMargin,
			CASE WHEN ISNULL(rLeft.BACommission,0) > 0 THEN ISNULL(rLeft.BACommission,0) ELSE 0 END		AS BACommission,		-- Negative number is displayed as 0
			CASE WHEN ISNULL(rRight.BACommission,0) > 0 THEN ISNULL(rRight.BACommission,0) ELSE 0 END	AS PreviousBACommission,
			ISNULL(rLeft.AmountToBA, 0)																	AS AmountDueToBA,		-- Keep as it is
			ISNULL(rRight.AmountToBA, 0)																AS PreviousAmountDueToBA,
			ISNULL(rLeft.SportsbookFee, 0)																AS SportsbookFee,
			ISNULL(rRight.SportsbookFee, 0)																AS PreviousSportsbookFee,
			ISNULL(rLeft.OthersFee,0) + ISNULL(rLeft.NegativeAmount,0)									AS OtherProductsFee,
			ISNULL(rRight.OthersFee,0) + ISNULL(rRight.NegativeAmount,0)								AS PreviousOtherProductsFee,
			CASE WHEN rLeft.SportbookDiscount > 0 THEN rLeft.SportbookDiscount ELSE 0 END				AS DiscountSportsbook,
			CASE WHEN ISNULL(rRight.SportbookDiscount,0) > 0 THEN rRight.SportbookDiscount ELSE 0 END	AS PreviousDiscountSportsbook,
			CASE WHEN rLeft.OthersDiscount > 0 THEN rLeft.OthersDiscount ELSE 0 END 					AS DiscountOthers,
			CASE WHEN ISNULL(rRight.OthersDiscount,0) > 0 THEN rRight.OthersDiscount ELSE 0 END			AS PreviousDiscountOthers,
			CASE WHEN rLeft.SportbookRebate > 0 THEN rLeft.SportbookRebate ELSE 0 END 					AS RebateSportsbook,
			CASE WHEN ISNULL(rRight.SportbookRebate,0) > 0 THEN rRight.SportbookRebate ELSE 0 END 		AS PreviousRebateSportsbook,
			CASE WHEN rLeft.OthersRebate > 0 THEN rLeft.OthersRebate ELSE 0 END 						AS RebateOthers,
			CASE WHEN ISNULL(rRight.OthersRebate,0) > 0 THEN rRight.OthersRebate ELSE 0 END 			AS PreviousRebateOthers,
			ISNULL(rLeft.PromotionSportsbook, 0)														AS PromotionSportsbook,
			ISNULL(rRight.PromotionSportsbook, 0)														AS PreviousPromotionSportsbook,
			ISNULL(rLeft.PromotionOthers, 0)															AS PromotionOthers,
			ISNULL(rRight.PromotionOthers, 0)															AS PreviousPromotionOthers,
			ISNULL(rLeft.TotalFee, 0) + ISNULL(rLeft.NegativeAmount,0) - ISNULL(rLeft.PromotionSportsbook,0) - ISNULL(rLeft.PromotionOthers,0)	AS TotalLicensingFee,
			ISNULL(rRight.TotalFee, 0) + ISNULL(rRight.NegativeAmount,0) - ISNULL(rRight.PromotionSportsbook,0) - ISNULL(rRight.PromotionOthers,0)	AS PreviousTotalLicensingFee
	FROM	(SELECT * FROM #Result WHERE IsCurrent = 1) rLeft
			FULL JOIN (SELECT * FROM #Result WHERE IsCurrent = 0) rRight ON rLeft.PartyId = rRight.PartyId
	WHERE	@LicenseePaying = 0 
			OR (@LicenseePaying = 1 AND rLeft.IsChargedByMinFee = 0 AND rLeft.IsChargedByGroupMinFee = 0)
			OR (@LicenseePaying = 2 AND rLeft.IsChargedByMinFee = 1)
			OR (@LicenseePaying = 3 AND rLeft.IsChargedByGroupMinFee = 1)
								
	) SELECT * FROM cte_Result r
	  INNER JOIN @PartyIdTable p ON r.PartyId = p.PartyId 
	  WHERE p.IsSelected = 1 AND (r.TotalTrans > 0 OR r.PreviousTotalTrans > 0 OR r.SportsbookFee > 0 OR r.PreviousSportsbookFee > 0)
	
	-- End region

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #Result
	DROP TABLE #AmountToCompany
	-- End region
END
GO