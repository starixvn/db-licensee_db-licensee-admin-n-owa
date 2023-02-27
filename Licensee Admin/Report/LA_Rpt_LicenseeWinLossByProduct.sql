/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinLossByProduct]
	@PartyIdString		VARCHAR(MAX)
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(10)
	,@LicenseeStatusIds	VARCHAR(100)
	,@PlatformId		TINYINT = 0
AS

/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee

	Revisions:
		+ 2015.08.06: Invoice Amount - Generate
		+ 2015.09.15: Get Amount by PartyId List.
		+ 2015.10.20@Bravo: Add Zelianta
		+ 2015.12.15@Bruce: Add MGCLC and MGCRNG
		+ 2016.05.05@Bravo: Add VB Data
		+ 2016.10.12@Bruce: Order result by group
		+ 2017.04.10@Scofield: Support AB and FW [#74738]
		+ 20170412: @Scofield - Removing Trading Bet Types [#73310]
		+ 20170605@Bruce: - Include Bettrade [#76131]
						  - Include Colossus bet [#76131]
						  - Include CashOut [#76131]
		- 20170704@Scofield: Add VS2 and LT into report [RedmineID: #79310]
		- 20171205@Bruce: fix partyid length [#87723]
		- 20180131@Scofield: Add BX [#87754]
		- 20180315@Bruce:Support Cozni licensees [#85681]
		- 20180419@Bruce: Implement Colossus Bets Freeplay(part 2) [#93907]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180510@Bruce: Integrate Pragmatic [#94108]
		- 20181119@bruce: Integrate Bidme games (GD product) [#103695]
	    - 20190322@Parsons: Integrate-PP-Promotion-Prize [#109014]
	    - 20190725@Mason: Integrate-Card-Club [#116096]
		- 20191121@Mason: Setup_billing_terms_by_Currency  [#120005]
	    - 20191205@Parsons: PP tournament [#123958]
	    - 20200226@Mason: Spadegaming-integration [#123959]
	    - 20200316@Parsons: Integrate Virtual Games [#125222]
	    - 20200409@Parsons: Integrate SA Gaming [#129276]
		- 20200423@Parsons: Intergrate Indo 4D [#130910]
		- 20200411@Parsons: Integrate Table Games [#131166]
		- 20200423@Parsons: Integrate Saba.club [#132730]
		- 20200507@Parsons: Integrate Sexy Gaming for deposit licensees [#132665]
		- 20200722@Happy: Implement PP Jackpot [#137306]
		- 20200909@Parsons: Implement PG Soft [RedmineID: #138983] 
		- 20200930@Parsons: Implement Joker Games [RedmineID: #141421]
		- 20201023@Parsons: Arcadia Gaming Add Bonus [#143597]
	    - 20201113@Parsons: Changing OddsSpread for licensee [#142345]
		- 20201209@Mason: Saba.club - Offer Freebet tickets [#141423]
		- 20201223@Happy: Implement WM [#141357]
		- 20201223@Parsons: Integrate Leap Gaming Virtual Sports [#145339]  
		- 20201230@Parsons: Integrate Gold Diamond Gaming [#145340] 
		- 20201231@Parsons: Integrate Big Gaming [#145342]
		- 20210106@Happy: Integrate MaxGame [#147375]
		- 20210202@Happy: Saba.club - Integrate Slot Game [#147977]
		- 20210219@Parsons: Add mini games bonus of Arcadia Gaming [#150248]
		- 20210407@Mason: Integrate new Sport Lottery [#150866]
		- 20210506@Percy: Integrate
			. Pragmatic Live Casino [RedmineID: #150971]
			. Habanero [RedmineID: #150636]
			. Creative Gaming [RedmineID: #152139]
		- 20210306@Danny: AE Sexy - Support Lucky Draw [#152141]
	    - 20210306@Danny: Integrate VGaming [#154080]
		- 20210614@Danny: Integrate AdvantPlay [#154787]
		- 20210614@Danny: Integrate AdvantPlay Mini [#155207]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20211212@Percy: Set OddsSpread = 0 if negative value [RedmineID: #165849]
		- 20210823@Danny: filter licensee status from OIC [#159296]
		- 20220110@Danny: SG - Jackpot prize integration [#167089]
		- 20220228@Danny: Allbet - Promotion integration [#167510]
		- 20220329@Danny: Intergrate Guaranteed Gaming [#167626]
		- 20220926@Danny: Intergrate MG-RNG [#176986]
		- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
		- 20220314@Danny: Incorporate USDTJP currency [RedmineID: #183461]
*/
		
/*	Example:
	USE bodb_Licensee
	DECLARe @PartyIdString	VARCHAR(500)	= '14,15,29,25,30'
	DECLARE @FromDate		DATETIME		= '2015-8-1'
	DECLARE @ToDate			DATETIME		= '2015-8-31'
	DECLARe @BaseCurrencyName	VARCHAR(10)		= 'GBP'
			
	EXEC [LA_Rpt_LicenseeWinLossByProduct] @PartyIdString, @FromDate, @ToDate, @BaseCurrencyName
	
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @FreeBetTicketType		TINYINT = 2, 
			@ProductCodes			VARCHAR(MAX),
			@ProductCodes_pivot		VARCHAR(MAX),	
			@SQL					VARCHAR(MAX),	
			@Delimiter				CHAR(1)=',',
			@CommChargeType			INT = 6,
	        @CashInShareChargeType	INT = 7
	
	DECLARE @PartyChargeInfo TABLE (ChargeId INT,PartyId INT,LicenseeId	INT,ProductID INT,BettypeRef INT,Rate MONEY,FromDate SMALLDATETIME,ToDate SMALLDATETIME)
	DECLARE @CBChargeRates TABLE (PartyId INT,LicenseeId INT,Rate MONEY,TypeId SMALLINT,FromDate DATETIME,ToDate DATETIME)
	DECLARE @ProductHaveExtraAmtList TABLE (ProductID INT)	

	CREATE TABLE #Products (GroupProductId INT, ProductId INT, ProductCode VARCHAR(100), ProductName VARCHAR(100))
	CREATE TABLE #Exchange (ExchangeDate DATE,ExchangeID INT,CurrencyCode VARCHAR(65),Rate FLOAT)
	CREATE TABLE #rpt_bettingByProduct (SiteID INT,rptDate DATETIME,CurrencyId INT,MemberWL MONEY,GrossWL MONEY,CommissionA MONEY,CommissionP MONEY,ProductId TINYINT, Bettype INT,
	Turnover MONEY, BuyBackAmount MONEY, WinPrizeAmount MONEY, ValidBetAmount MONEY, TicketType TINYINT, ExtraAmount MONEY, CashOutAmount MONEY)
	CREATE TABLE #TempData (LicenseeId	INT,rptDate	DATETIME,CurrencyId	INT,MemberWL MONEY,AWinLoss	MONEY,AComm	MONEY,PComm	MONEY,ProductId	TINYINT,BettypeRef INT)
	CREATE TABLE #Result(PartyID INT,ProductID INT,Amount MONEY)
	CREATE TABLE #PartyIdTable (Id INT NOT NULL, StatusID INT)
	CREATE TABLE #TempPartyList (PartyId INT,PartyName VARCHAR(200),BranchName	VARCHAR(200),ParentId INT)
	-- Get Product List
	BEGIN
		INSERT INTO #Products (GroupProductId, ProductId, ProductCode, ProductName)
		SELECT GroupProductId, ProductId, ProductCode ,ProductName
		FROM   dbo.LA_f_GroupProduct('', @FromDate, @ToDate) g
		WHERE g.ProductId NOT IN (
			1, 4, 7, 9, 12, 14, 17, 30, 33 -- inactive
			,16 -- Hosting (setting only)
			,13, 23 -- BT, NG2
			,46, 47, 50, 52 -- don't offer
		)
		SELECT	@ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode
		FROM #Products

		SELECT	@ProductCodes_pivot = COALESCE(@ProductCodes_pivot + ',', '') + '[' + ProductCode + ']'
		FROM #Products WHERE GroupProductId = ProductId
		ORDER BY ProductId

		INSERT INTO @ProductHaveExtraAmtList(ProductID)
		SELECT DISTiNCT ProductId FROM LA_f_GroupBettype() WHERE TypeId NOT IN (1,7)
	END
	
	-- Handle Licensee status
	SELECT @PartyIdString = PartyIDs FROM dbo.LA_f_PartyListByStatusSel(@PartyIdString, @LicenseeStatusIds)
	-- End Handle Licensee status

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIdString = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIdString, ',')) 
	END

	-- Region: Get Party ID
	INSERT #PartyIdTable (Id)
	SELECT value FROM STRING_SPLIT(@PartyIdString, @Delimiter)
	-- End Region

	INSERT INTO @PartyChargeInfo(ChargeId, PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, BettypeRef)
	SELECT	ChargeId, PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate, 
			CASE
				WHEN ProductId = 11 AND ChargeType = 12 THEN 1706 --GD Tip
				WHEN ProductId = 39 AND ChargeType = 12 THEN 3007 --SAG_Tip
			ELSE Bettype
		END
	FROM	dbo.LA_f_ChargeInfo(@PartyIdString, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
	WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB

	-- Region: Get exchange rate info
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End region
	
	-- Region: Get Winloss data
	INSERT INTO #rpt_bettingByProduct(SiteID,rptDate,CurrencyId,MemberWL,GrossWL,CommissionA,CommissionP,ProductId,Bettype,Turnover, BuyBackAmount, WinPrizeAmount, ValidBetAmount, TicketType,ExtraAmount, CashOutAmount)
	SELECT	b.SiteID,
			b.rptDate,
			b.CurrencyID,
			SUM(ISNULL(b.MemberWL, 0)) Winloss,
			SUM(ISNULL(b.GrossWL, 0)) AS AWinLoss,
			SUM(ISNULL(b.CommissionA, 0)) AS AComm,
			SUM(ISNULL(b.CommissionP, 0)) AS PComm,
			t.GroupProductId AS ProductId,
			b.Bettype,
			SUM(ISNULL(Turnover,0)) Turnover,
			SUM(ISNULL(BuyBackAmount,0)) BuyBackAmount,
			SUM(ISNULL(WinPrizeAmount,0)) WinPrizeAmount,
			SUM(ISNULL(ValidBetAmount,0)) ValidBetAmount,
			TicketType,
			SUM(ISNULL(ExtraAmount,0)) ExtraAmount,
			SUM(ISNULL(CashOutAmount,0)) CashOutAmount
	FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
	INNER JOIN #Products t ON b.ProductId = t.ProductId
	WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.customercategory NOT IN (27, 28)
	GROUP BY b.rptdate, b.SiteId, b.CurrencyID, t.GroupProductId, b.Bettype, b.TicketType
	CREATE CLUSTERED INDEX CIX_#rpt_bettingByProduct ON #rpt_bettingByProduct(ProductId, SiteID)

	INSERT INTO #TempData (LicenseeId,rptDate,CurrencyId,MemberWL,AWinLoss,AComm,PComm,ProductId,BettypeRef)
	SELECT	b.SiteID,
			b.rptDate,
			b.CurrencyID,
			SUM(ISNULL(b.MemberWL, 0)) Winloss,
			SUM(ISNULL(b.GrossWL, 0)) AS AWinLoss,
			SUM(ISNULL(b.CommissionA, 0)) AS AComm,
			SUM(ISNULL(b.CommissionP, 0)) AS PComm,
			t.GroupProductId AS ProductId,
			CASE WHEN b.Bettype IN (1706,999) THEN b.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END AS BettypeRef
	FROM	#rpt_bettingByProduct b
			INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON b.SiteID = p.OldRefID AND p.PartyType = 1
			INNER JOIN #Products t ON b.ProductId = t.ProductId
			LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.Bettype = b.Bettype
			LEFT JOIN LA_f_ExcludedBettypeListSel('','1706,999') eb ON b.Bettype = eb.BettypeID
	WHERE	( b.ProductID NOT IN (15,25)
			OR b.ProductId NOT IN (SELECT x.ProductID FROM @ProductHaveExtraAmtList x)
			) AND eb.BettypeID IS NULL
	GROUP BY b.rptdate, b.SiteId, b.CurrencyID, t.GroupProductId, CASE WHEN b.Bettype IN (1706,999) THEN b.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END
	CREATE CLUSTERED INDEX #TempData ON #TempData(ProductId, LicenseeId)
	-- EndRegion

	-- Region: Generate licensee name & group
	INSERT INTO #TempPartyList(PartyId,PartyName,BranchName,ParentId)
	EXECUTE dbo.LA_PartyListSel
	
	;WITH AmountDueBA AS
	(
		SELECT	p.PartyId,
				SUM(-(MemberWL + AComm) * e.Rate) Amount
		FROM	#TempData d
				INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON d.LicenseeId = p.LicenseeId AND d.ProductId = p.ProductId AND d.rptDate BETWEEN p.FromDate AND p.ToDate
		WHERE	d.ProductId = 3
		GROUP	BY p.PartyId
	)
	INSERT INTO #Result(PartyID, ProductID, Amount)
	SELECT d.PartyID,3,Amount  FROM AmountDueBA d
	-- End BA

	-- CB
	INSERT INTO @CBChargeRates(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)
	SELECT PartyID,LicenseeID,DI_Rate,ChargeType,Fromdate,Todate
	FROM dbo.LA_f_ChargeInfo(@PartyIdString,@FromDate,@ToDate,'CB','OA',1)

	;WITH t AS (
		SELECT b.SiteId, b.rptDate,
			SUM(Turnover* e.Rate) Turnover,
			SUM(CASE WHEN ISNULL(TicketType,0)=0 THEN Turnover ELSE ISNULL(ExtraAmount,0) END * e.Rate) TurnoverForCommission,
			SUM(ISNULL(WinPrizeAmount * e.Rate,0)) WinningPrize,
			SUM(ISNULL(CashOutAmount * e.Rate,0)) CashOut,
			SUM(ISNULL(BuyBackAmount * e.Rate,0)) CashInAmount
		FROM #rpt_bettingByProduct b
		INNER JOIN @CBChargeRates cb ON b.SiteID = cb.LicenseeId AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
		INNER JOIN #Exchange e ON e.ExchangeID=b.CurrencyId AND e.ExchangeDate = b.rptDate
		WHERE b.ProductID = 15
			AND cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
		GROUP BY b.rptDate, b.SiteId
	)INSERT INTO #Result(PartyID, ProductID, Amount)
	SELECT cm.PartyId,15,SUM(t.Turnover) - SUM(t.WinningPrize) - SUM(t.CashOut) - SUM(t.TurnoverForCommission * cm.Rate) - SUM(t.CashInAmount * ci.Rate)
	FROM t
	INNER JOIN @CBChargeRates AS cm ON cm.TypeId = @CommChargeType AND (t.rptDate BETWEEN cm.FromDate AND cm.ToDate) AND cm.LicenseeId=t.SiteID
	INNER JOIN @CBChargeRates AS ci ON ci.TypeId = @CashInShareChargeType AND (t.rptDate BETWEEN ci.FromDate AND ci.ToDate) AND ci.LicenseeId=t.SiteID
	GROUP BY cm.PartyId
	-- End CB

	-- CO
	;WITH t AS (
		SELECT p.PartyId,
			SUM(b.BuyBackAmt * e.Rate) AS BuyBackAmountSB,
			SUM(b.BABuyBackAmt * e.Rate) AS BuyBackAmountBA,
			SUM(b.TicketPayout * e.Rate) AS TicketsPayout,					
			SUM(b.BuyBackAmt * p.Rate * e.Rate) AS CashoutCommission	
		FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON b.SiteId = p.LicenseeID AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate AND p.ProductID = b.ProductID
			INNER JOIN #Exchange e ON e.ExchangeID = b.Currency AND e.ExchangeDate = b.Winlostdate
		WHERE b.Winlostdate BETWEEN p.FromDate AND p.ToDate									
			AND b.Currency <> 20
			AND b.RoleID = 1 -- Member
		GROUP BY p.PartyId
	)
	INSERT INTO #Result(PartyId, ProductID, Amount)
	SELECT PartyId, 25, SUM(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission)
	FROM t
	GROUP BY t.PartyId
	-- End CO
	
	-- Product Have Extra Amount
	;WITH cte_WinLossData AS 
	(
		SELECT b.SiteId, b.rptDate, b.CurrencyID, b.ProductID,
			SUM(CASE WHEN ISNULL(b.TicketType,0) = @FreeBetTicketType OR bt.TypeId IN (2,3,4,5,6,8) THEN 0 
				ELSE (ISNULL(-b.MemberWL, 0) * e.Rate) END) AS LicenseeWL,
			SUM(CASE WHEN bt.TypeId = 2 THEN ISNULL(-b.GrossWL, 0) ELSE 0 END * e.Rate) AS Contribution,
			SUM(CASE WHEN bt.TypeId = 3 THEN ISNULL(b.MemberWL, 0) ELSE 0 END * e.Rate) AS JackpotPrize,
			SUM(CASE WHEN bt.TypeId IN (4,5,6,8) OR ISNULL(b.TicketType,0) = @FreeBetTicketType THEN ISNULL(b.MemberWL, 0) ELSE 0 END * e.Rate) AS ExtraAmount
		FROM #rpt_bettingByProduct b
		INNER JOIN #Exchange e ON e.ExchangeID = b.CurrencyId AND e.ExchangeDate = b.rptDate
		INNER JOIN @ProductHaveExtraAmtList p ON b.ProductId = p.ProductID
		LEFT JOIN  LA_f_GroupBettype() bt ON b.Bettype = bt.Bettype
		GROUP BY b.rptdate, b.SiteId, b.CurrencyID, b.ProductID
	), cte_LicensingWL AS
	(
		SELECT p.PartyId, d.ProductID,  d.SiteID,
			SUM((LicenseeWL - Contribution) * ISNULL(cr.Rate, p.Rate)) LicensingFee, 
			SUM(d.Contribution) Contribution,
			SUM(d.JackpotPrize) JackpotPrize, 
			SUM(d.ExtraAmount)	ExtraAmount
		FROM cte_WinLossData d
		INNER JOIN @PartyChargeInfo p ON p.LicenseeId = d.SiteId AND (d.rptDate BETWEEN p.FromDate AND p.ToDate) AND p.ProductID = d.ProductID
		LEFT JOIN LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = p.ChargeID AND d.CurrencyId = cr.CurrencyID
		WHERE d.rptDate BETWEEN p.Fromdate AND p.Todate
		GROUP BY p.PartyId, d.ProductID,  d.SiteID
	), cte_LicensingFee AS
	(
		SELECT l.PartyId, l.SiteID, l.ProductId, CASE WHEN l.LicensingFee < 0 AND jvp.PartyId IS NULL THEN 0 ELSE l.LicensingFee END AS LicensingFee,
			l.Contribution, l.JackpotPrize, l.ExtraAmount
		FROM cte_LicensingWL l
			LEFT JOIN dbo.LA_f_JVPartyListSel() jvp ON l.PartyId = jvp.PartyId
	)
	INSERT INTO #Result(PartyId, ProductID, Amount)
	SELECT	 PartyId, 
			 ProductId,
			 LicensingFee + Contribution - JackpotPrize - ExtraAmount
	FROM cte_LicensingFee
	--End PP, SBC, Arcadia_Gaming

	-- SportsBook
	;WITH cte_SBWinLost AS
	(
		SELECT  ci.PartyID
		, SUM(CASE WHEN b.BettypeRef = 999 THEN 0 ELSE ISNULL(-b.MemberWL, 0) END * ISNULL(cr.Rate, ci.Rate) * e.Rate) AS LicencingFee
		, SUM(CASE WHEN b.BettypeRef = 999 THEN ISNULL(-b.AWinLoss, 0) ELSE 0 END * e.Rate) AS OddsSpreadCost
		FROM #TempData b
		INNER JOIN @PartyChargeInfo ci ON b.LicenseeId = ci.LicenseeId AND b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
		INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND b.CurrencyId = cr.CurrencyID
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.ProductID = 0 -- SB
		GROUP BY ci.PartyId
	)
	INSERT INTO #Result(PartyId, ProductID, Amount)
	SELECT PartyId, 0, cte.LicencingFee + CASE WHEN cte.OddsSpreadCost < 0 THEN 0 ELSE cte.OddsSpreadCost END
	FROM cte_SBWinLost cte
	-- End SportsBook

	-- Calculate amount for other products 
	INSERT INTO #Result(PartyId, ProductID, Amount)
	SELECT ci.PartyId, d.ProductId, 
			SUM(CASE WHEN d.ProductID = 31 THEN  (-MemberWL * ci.Rate - (AComm + PComm)) * e.Rate
					ELSE -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate END)
	FROM	#TempData d
	INNER JOIN @PartyChargeInfo ci ON	d.LicenseeId = ci.LicenseeId
										AND ci.ProductId = d.ProductId
										AND d.rptDate BETWEEN ci.FromDate AND ci.ToDate
										AND d.BettypeRef = ci.BettypeRef
	LEFT JOIN dbo.LA_ChargeRateByCurrency cm WITH (NOLOCK) ON ci.ChargeId = cm.ChargeId AND d.CurrencyId = cm.CurrencyId
	INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
	WHERE d.ProductId NOT IN (0,3,15,25) AND d.ProductId NOT IN (SELECT x.ProductID FROM @ProductHaveExtraAmtList x)
	GROUP BY ci.PartyId, d.ProductId
	-- End calculate amount

	-- Result
	SET @SQL = '
		;WITH t AS
		(
		SELECT	REPLACE(p.PartyName,'' Licensees'','''') AS GroupName,
				p.PartyId GroupId,
				op.OldRefID LicenseeId,
				t.PartyId PartyId, 
				t.PartyName PartyName
		FROM	#TempPartyList t INNER JOIN #TempPartyList p ON t.ParentId = p.PartyId
				INNER JOIN dbo.OAS_Party op WITH (NOLOCK) ON op.PartyID = t.PartyId
		WHERE	t.ParentId != 0
				AND t.PartyId IN (SELECT Id FROM #PartyIdTable)
		),u AS
		(
		SELECT t.GroupName,t.PartyName, p.ProductCode, r.Amount 
		FROM #Result r
		INNER JOIN #Products p ON r.ProductID = p.ProductID
		LEFT JOIN t ON r.PartyId = t.PartyId
		)
		SELECT GroupName ,PartyName, ' + @ProductCodes_pivot + '
		FROM (SELECT GroupName, PartyName, ProductCode, Amount  FROM  u) u
		PIVOT (
			MAX(u.Amount) FOR ProductCode IN (' + @ProductCodes_pivot + ')
		) p
		ORDER BY GroupName, PartyName
	'
	EXEC (@SQL)
	-- EndRegion

	DROP TABLE #Result
	DROP TABLE #rpt_bettingByProduct
	DROP TABLE #Exchange
	DROP TABLE #Products
	DROP TABLE #TempData
	DROP TABLE #TempPartyList
	DROP TABLE #PartyIdTable
END
GO