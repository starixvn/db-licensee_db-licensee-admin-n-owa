/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb02]
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
	, @ExcludeTest BIT = 0
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

	Param's Explanation:  
	  + @PartyIDs : a string of list LicenseeID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
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
		WHERE	PartyGroupId IN (	SELECT	p1.PartyGroupId
									FROM	bodb_licensee.dbo.LA_PartyGroupAssignment p1 WITH(NOLOCK)
									WHERE	p1.PartyId IN (SELECT p2.PartyId FROM @PartyIdTable p2))
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
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID and map.SystemID = 2
		WHERE	ci.FromParty IN (SELECT PartyId FROM @PartyIdTable) AND
				ci.ProductId NOT IN (SELECT DISTINCT ProductId FROM bodb_licensee.dbo.LA_Product3rdSub)
		UNION ALL
		SELECT s.FromDate, ci.FromParty
		FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping map ON map.ChargeID = ci.ChargeID and map.SystemID = 2
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
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			Bettype		INT)

	-- ***********************************************************************************************
	-- *** Get ChargeInfo for @PartyIDs in 2 period: FromDate-ToDate, PreviousFromDate-PreviousToDate
	-- ***********************************************************************************************
	-- select bettype to avoid duplicated data of MGC
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate, 
				CASE WHEN @ExcludeTest=1 THEN ci.Fromdate ELSE @Fromdate END, 	-- include trial data
				CASE WHEN @ExcludeTest=1 THEN ci.ToDate ELSE @ToDate END,		-- include trial data
				CASE WHEN ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @ExcludeTest) ci
		LEFT JOIN bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	((ci.PartyID IN (25,30,324) AND DI_Rate = 0) OR DI_Rate > 0) AND ProductId <> 1 --exclude RB
	)
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate,
				CASE WHEN @ExcludeTest=1 THEN ci.Fromdate ELSE @PrevFromDate END,	-- include trial data
				CASE WHEN @ExcludeTest=1 THEN ci.ToDate ELSE @PrevToDate END,		-- include trial data
				CASE WHEN ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @PrevFromDate, @PrevToDate, @ProductCodes, 'OA', @ExcludeTest) ci
		LEFT JOIN bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
		WHERE	((ci.PartyID IN (25,30,324) AND DI_Rate = 0) OR DI_Rate > 0) AND ProductId <> 1 --exclude RB
	)
	-- End region

	-- *************************************************************************************************************
	-- *** Get minfee, waive when @Currency = 0 (all currencies) for 2 periods (current period and previous period)
	-- *** - minfee: FeeType = 1, waive: FeeType = 2
	-- *** - conditions: Product is in (PartyChargeInfo)
	-- *** - waive: select only waive which has corresponding minfee config
	-- *************************************************************************************************************
	--  Minimum fee is calculated for all currencies that licensee offer. There is no minimum fee when data display individual currency.
	IF @Currency = 0
	BEGIN
		-- Region: MinfeeGroup Date range
		DECLARE @Month TINYINT = MONTH(@FromDate)
		DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
		DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
		DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1
		DECLARE @PrevFirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @PrevFromDate), 0)
		DECLARE @PrevLastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @PrevFromDate) + 1, 0))
		DECLARE @PrevDaysInMonth INT = DATEDIFF(day, @PrevFirstDate, @PrevLastDate) + 1

		DECLARE @MinFeeGroup TABLE(
				IsCurrent		BIT,
				FeeType			TINYINT,
				PartyId			INT,
				ProductId		INT,
				CurrencyId		INT,
				FeeAmount		MONEY,
				FromDate		DATETIME,
				ToDate			DATETIME,
				MinFeeProrate	MONEY,
				WaivedAmount	MONEY,
				TotalAmount		MONEY,
				MinFeeAmount	MONEY,
				AmountToCompany	MONEY)

		INSERT INTO @MinFeeGroup(IsCurrent, FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
		(
			SELECT	1 AS IsCurrent,
					mf.FeeTypeId,
					mf.PartyId,
					mf.ProductId,
					mf.CurrencyId,
					mf.FeeAmount,
					CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
					CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate
			FROM	bodb_licensee.dbo.LA_MinFee mf WITH(NOLOCK)
			WHERE	((mf.FeeTypeId = 1)
						OR mf.FeeTypeId = 2 AND EXISTS (SELECT	PartyId
														FROM	bodb_licensee.dbo.LA_MinFee m WITH(NOLOCK)
														WHERE	m.FeeTypeId = 1
																AND m.PartyId = mf.PartyId
																AND m.ProductId = mf.ProductId
																AND ((m.FromDate BETWEEN @FirstDate AND @LastDate)
																	OR (m.ToDate BETWEEN @FirstDate AND @LastDate)
																	OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
																)
														)
					)
					AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
					AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
						OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
						OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
					)
		)

		SELECT	@FirstDate = DATEADD(mm, DATEDIFF(mm, 0, @PrevFromDate), 0)
		SELECT	@LastDate = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @PrevFromDate) + 1, 0))
		DECLARE @DaysInPrevMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

		INSERT INTO @MinFeeGroup(IsCurrent, FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
		(
			SELECT	0 AS IsCurrent,
					mf.FeeTypeId,
					mf.PartyId,
					mf.ProductId,
					mf.CurrencyId,
					mf.FeeAmount,
					CASE WHEN @PrevFromDate >= mf.FromDate THEN @PrevFromDate ELSE mf.FromDate END AS FromDate,
					CASE WHEN @PrevToDate < mf.ToDate THEN @PrevToDate ELSE mf.ToDate END AS ToDate
			FROM	bodb_licensee.dbo.LA_MinFee mf WITH(NOLOCK)
			WHERE	((mf.FeeTypeId = 1)
						OR mf.FeeTypeId = 2 AND EXISTS (SELECT	PartyId
														FROM	bodb_licensee.dbo.LA_MinFee m WITH(NOLOCK)
														WHERE	m.FeeTypeId = 1 
																AND m.PartyId = mf.PartyId
																AND m.ProductId = mf.ProductId
																AND ((m.FromDate BETWEEN @FirstDate AND @LastDate) 
																	OR (m.ToDate BETWEEN @FirstDate AND @LastDate) 
																	OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
																)
														)
					)
					AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
					AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
						OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
						OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
					)
		)

		DELETE	FROM @MinFeeGroup
		WHERE	(FeeType = 2 AND FromDate > ToDate) OR
				(PartyId NOT IN (SELECT g.PartyId FROM @PartyGroup g) AND
					PartyId NOT IN (SELECT p.PartyId FROM @PartyIdTable p))
	END
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

	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END
	-- End region

	UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
	INNER JOIN #Exchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID

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
				SUM(b.BetCount * CASE WHEN @DrawFilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END),
				SUM(b.Turnover * CASE WHEN @DrawFilter IN (2, 3) 
										THEN CASE	WHEN b.StatusId = 111 THEN 0
													WHEN b.StatusId IN (114, 115) THEN 0.5
											 ELSE 1 END
										ELSE 1 END) * e.Rate,
				SUM(ISNULL(b.MemberWL, 0)) * e.Rate,
				SUM(ISNULL(b.CommissionA, 0)) * e.Rate,
				SUM(ISNULL(b.CommissionP, 0)) * e.Rate,
				p.ProductId,
				SUM((-ISNULL(b.MemberWL, 0) * p.Rate) - (CASE 
					WHEN b.ProductId = 3 THEN ISNULL(b.CommissionA, 0) -- BA
					WHEN b.ProductID = 31 THEN ISNULL(b.CommissionA, 0) + ISNULL(b.CommissionP, 0) -- Exchange
					ELSE 0 END)) * e.Rate
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate OR b.rptDate BETWEEN @PrevFromDate AND @PrevToDate)
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, e.Rate
	)

	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId, ProductId)

--  Minimum fee is calculated for all currencies that licensee offer. There is no minimum fee when data display individual currency.
	IF @Currency = 0
	BEGIN
		UPDATE  t
		SET		t.IsApplyMinFee = 0
		FROM	#TempData t INNER JOIN @MinFeeGroup m ON (t.rptDate BETWEEN m.FromDate AND m.ToDate OR t.rptDate BETWEEN @PrevFromDate AND @PrevToDate)
				AND t.ProductId = m.ProductId
				AND t.PartyId = m.PartyId
		WHERE	m.FeeType=2
		-- End region

		-- Region: Check min fee group
		--- calculate waived prorate (*)
		UPDATE	amf
		SET		MinFeeProrate = ((	SELECT	TOP 1 mfg.FeeAmount
									FROM	@MinFeeGroup mfg
									WHERE	mfg.FeeType = 1
											AND amf.IsCurrent = mfg.IsCurrent
											AND mfg.PartyId = amf.PartyId
											AND mfg.ProductId = amf.ProductId)
								/ (CASE WHEN amf.IsCurrent = 1 THEN @DaysInMonth ELSE @PrevDaysInMonth END)) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
		FROM	@MinFeeGroup amf
		WHERE	FeeType = 2

		--- sum amount under waived
		UPDATE	amf
		SET		amf.WaivedAmount = ISNULL((	SELECT	SUM(td.AmountToCompany)
											FROM	#TempData td 
											WHERE	amf.PartyId = td.PartyId
													AND amf.ProductId = td.ProductId
													AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate), 0)
		FROM	@MinFeeGroup amf
		WHERE	amf.FeeType = 2

		--- calculate min fee prorate (fee amount in month - waived amount (*)
		UPDATE	amf
		SET		amf.MinFeeProrate = ROUND((	amf.FeeAmount / (CASE WHEN amf.IsCurrent = 1 THEN @DaysInMonth ELSE @PrevDaysInMonth END)) * (DATEDIFF(DAY, FromDate, ToDate) + 1) -
											ISNULL((SELECT	SUM(f.MinFeeProrate)
													FROM	@MinFeeGroup f
													WHERE	f.FeeType = 2
															AND amf.IsCurrent = f.IsCurrent
															AND amf.PartyId = f.PartyId
															AND amf.ProductId = f.ProductId), 0), 2),
				amf.WaivedAmount =  ISNULL((SELECT	CASE WHEN SUM(f.WaivedAmount) < 0 THEN 0 ELSE SUM(f.WaivedAmount) END
											FROM	@MinFeeGroup f
											WHERE	f.FeeType = 2
													AND amf.IsCurrent = f.IsCurrent
													AND amf.PartyId = f.PartyId
													AND amf.ProductId = f.ProductId), 0),
				amf.MinFeeAmount =  ISNULL((SELECT	SUM(td.AmountToCompany)
											FROM	#TempData td 
											WHERE	amf.PartyId = td.PartyId
													AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
													AND td.IsApplyMinFee IS NULL
													AND amf.ProductId = td.ProductId), 0)
		FROM	@MinFeeGroup amf
		WHERE	amf.FeeType = 1
		--- sum min fee amount
		UPDATE	amf
		SET		amf.TotalAmount =  amf.MinFeeAmount + amf.WaivedAmount
		FROM	@MinFeeGroup amf
		WHERE	amf.FeeType = 1
	
		DECLARE @TotalMinFees TABLE(
			PartyGroupId		INT,
			ProductId			INT,
			TotalMinFee			MONEY,
			TotalMinFeeAmount	MONEY,
			IsCurrent			BIT
		)
		INSERT	INTO @TotalMinFees(PartyGroupId, ProductId, IsCurrent, TotalMinFee, TotalMinFeeAmount)
		SELECT	pg.PartyGroupId, mf.ProductId, mf.IsCurrent,
				SUM(mf.MinFeeProrate),
				SUM(CASE WHEN mf.MinFeeAmount < 0 THEN 0 ELSE mf.MinFeeAmount END)
		FROM	@MinFeeGroup mf
		INNER JOIN @PartyGroup pg ON mf.PartyId = pg.PartyId
		WHERE	mf.FeeType = 1
		GROUP BY pg.PartyGroupId,mf.ProductId,mf.IsCurrent

		-- update minfee group
		UPDATE	amf
		SET		amf.AmountToCompany =	CASE
											WHEN t.TotalMinFeeAmount < t.TotalMinFee AND amf.MinFeeAmount < amf.MinFeeProrate 
												THEN amf.MinFeeProrate + amf.WaivedAmount
											ELSE amf.TotalAmount
										END
		FROM	@MinFeeGroup amf
		INNER JOIN @PartyGroup pg ON pg.PartyId = amf.PartyId
		INNER JOIN @TotalMinFees t ON amf.ProductId = t.ProductId AND t.PartyGroupId = pg.PartyGroupId AND t.IsCurrent = amf.IsCurrent
		WHERE	amf.FeeType = 1
		
		-- update minfee non-group
		UPDATE	amf
		SET		amf.AmountToCompany =	CASE WHEN amf.MinFeeAmount < amf.MinFeeProrate
												THEN amf.MinFeeProrate + amf.WaivedAmount
											ELSE amf.TotalAmount
										END
		FROM	@MinFeeGroup amf
		WHERE	amf.FeeType = 1 AND amf.AmountToCompany IS NULL
	END
	
	-- ********************************************************************************************
	-- *** Get Discount and Rebate Headers
	-- *** Conditions: FromDate-ToDate intersect with @FromDate-@ToDate (@PreFromDate, @PreToDate)
	-- ********************************************************************************************
	-- Region: Discount & Rebate Settings
	BEGIN
	DECLARE @DiscountGroupHeader AS TABLE (
			DiscountGroupId		INT,
			DiscountGroupType	TINYINT,
			PartyId				INT,
			CurrencyId			INT,
			FromDate			DATETIME,
			ToDate				DATETIME,
			IsCurrent			BIT)

	INSERT INTO @DiscountGroupHeader(DiscountGroupId,DiscountGroupType,PartyId,CurrencyId,FromDate,ToDate,IsCurrent)
	(
		SELECT	dg.DiscountGroupId,dg.DiscountGroupType,dga.PartyId, dg.CurrencyId, dg.FromDate, dg.ToDate, 1
		FROM	bodb_Licensee.dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment dga WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		WHERE	@FromDate<= ToDate AND FromDate<=@ToDate
	)

	INSERT INTO @DiscountGroupHeader(DiscountGroupId,DiscountGroupType,PartyId,CurrencyId,FromDate,ToDate,IsCurrent)
	(
		SELECT	dg.DiscountGroupId,dg.DiscountGroupType,dga.PartyId, dg.CurrencyId, dg.FromDate, dg.ToDate, 0
		FROM	bodb_Licensee.dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment dga WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		WHERE	@PrevFromDate<= ToDate AND FromDate<=@PrevToDate
	)

	-- ********************************************
	-- *** Get the lastest discount/rebate headers
	-- ********************************************
	DECLARE @DiscountGroupType INT = 1
	WHILE @DiscountGroupType <= 2
	BEGIN
		DELETE	d FROM @DiscountGroupHeader d
		WHERE	d.ToDate < (SELECT	MAX(g.ToDate)
					FROM	@DiscountGroupHeader g
					WHERE	g.DiscountGroupType = @DiscountGroupType AND g.IsCurrent = 1 AND d.PartyId = g.PartyId)
			AND d.DiscountGroupType = @DiscountGroupType AND d.IsCurrent = 1
			
		DELETE	d FROM @DiscountGroupHeader d
		WHERE	d.ToDate < (SELECT	MAX(g.ToDate)
					FROM	@DiscountGroupHeader g
					WHERE	g.DiscountGroupType = @DiscountGroupType AND g.IsCurrent = 0 AND d.PartyId = g.PartyId)
			AND d.DiscountGroupType = @DiscountGroupType AND d.IsCurrent = 0
			
	   SET @DiscountGroupType = @DiscountGroupType + 1
	END

	-- **********************************************
	-- *** Get Discount/Rebate Settings Infos
	-- *** Conditions: ProductId in (PartyChargeInfo)
	-- **********************************************
	DECLARE @DiscountGroup AS TABLE(
			DiscountGroupId		SMALLINT,
			DiscountGroupType	TINYINT,
			FromAmount			MONEY,
			ToAmount			MONEY,
			Rate				MONEY,
			PartyId				INT,
			ProductId			TINYINT,
			BaseCurrency		INT,
			IsCurrent			BIT)

	INSERT INTO @DiscountGroup (DiscountGroupId, DiscountGroupType, FromAmount, ToAmount, Rate, PartyId, ProductId , BaseCurrency, IsCurrent)	
	(
		SELECT	dg.DiscountGroupId,
				dg.DiscountGroupType,
				dgd.FromAmount,
				dgd.ToAmount,
				dgd.Rate,
				dg.PartyID,
				dgp.ProductId,
				dg.CurrencyId,
				dg.IsCurrent
		FROM	@DiscountGroupHeader dg 
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dg.DiscountGroupId = dgd.DiscountGroupId
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dg.DiscountGroupId = dgp.DiscountGroupId
		WHERE	dgp.ProductId IN ( SELECT DISTINCT ProductId FROM @PartyChargeInfo)
	)

	-- ***************************************************************
	-- *** Convert Discount FromAmount, ToAmount to @BaseCurrencyName
	-- *** Notes: Rebate does not have FromAmount, ToAmount
	-- ***************************************************************
	-- convert discount amount to base currency
	UPDATE d SET
		d.FromAmount = d.FromAmount * e.Rate,
		d.ToAmount = d.ToAmount * e.Rate
	FROM @DiscountGroup d
	INNER JOIN #Exchange e ON
		e.ExchangeDate =(CASE WHEN d.IsCurrent = 1 THEN @ToDate ELSE @PrevToDate END) AND
		d.BaseCurrency = e.ExchangeID AND
		d.DiscountGroupType = 1 -- discount = 1
	END
	-- End Region

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
			HasMinFee		BIT
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

		-- merge to minfee group
		UPDATE s SET AmountToCompany = m.AmountToCompany, hasMinFee = CASE WHEN m.AmountToCompany=m.TotalAmount THEN 0 ELSE 1 END
		FROM @SumByProducts s
		INNER JOIN @MinFeeGroup m ON m.PartyId = s.PartyId AND m.IsCurrent = s.IsCurrent AND m.ProductId = s.ProductId
		WHERE m.FeeType = 1 -- min fee
		
		-- insert data for party-product which has min fee but doesn't has bet ticket
		INSERT INTO @SumByProducts(PartyId, ProductId, IsCurrent, AmountToCompany, HasMinFee, BetCount, Turnover, WinLoss, AComm)
		SELECT m.PartyId, m.ProductId, m.IsCurrent, m.AmountToCompany, 1, 0, 0, 0, 0
		FROM @MinFeeGroup m
		LEFT JOIN @SumByProducts s ON m.PartyId = s.PartyId AND m.ProductId = s.ProductId AND m.IsCurrent = s.IsCurrent
		WHERE m.FeeType = 1 AND s.PartyId IS NULL	

		-- filter discount
		;WITH t AS(
			SELECT SUM(s.AmountToCompany) Total, s.PartyId, s.IsCurrent,d.DiscountGroupId
			FROM @SumByProducts s
			INNER JOIN (SELECT DISTINCT DiscountGroupId,PartyId,ProductId,IsCurrent FROM @DiscountGroup WHERE DiscountGroupType = 1) AS d
				ON s.PartyId=d.PartyId AND s.ProductId=d.ProductId AND s.IsCurrent=d.IsCurrent
			GROUP BY s.PartyId, d.DiscountGroupId, s.IsCurrent
		)
		DELETE d
		FROM @DiscountGroup d
		INNER JOIN t ON t.DiscountGroupId = d.DiscountGroupId AND t.PartyId = d.PartyId AND t.IsCurrent = d.IsCurrent
		WHERE d.DiscountGroupType = 1 AND t.Total NOT BETWEEN d.FromAmount AND d.ToAmount
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
		TotalFee			MONEY,
		NegativeAmount		MONEY,
		IsCurrent			BIT
	)

	-- ************************************
	-- *** Calculate #Result for SportBook
	-- ************************************
	INSERT INTO #Result (PartyId, ProductId, PartyName, SportsbookFee, IsCurrent, BetCount, AverageBet, Turnover, WinLoss, Margin, OthersFee, SportbookDiscount, BACommission)
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
			(CASE WHEN -s.WinLoss < 0 THEN 0 ELSE -s.WinLoss * ISNULL(d3.Rate, 0) END) + (CASE WHEN s.AmountToCompany < 0 THEN 0 ELSE s.AmountToCompany * ISNULL(d1.Rate, 0) END) AS SportbookDiscount,
			0 AS BACommission
	FROM	@PartyIdTable p
			INNER JOIN bodb_licensee.dbo.OAS_Party (NOLOCK) op ON p.PartyId = op.PartyID
			INNER JOIN @SumByProducts s ON p.PartyId = s.PartyId
			LEFT JOIN @DiscountGroup d1 ON s.PartyId = d1.PartyId AND s.IsCurrent = d1.IsCurrent AND d1.ProductId = s.ProductId AND d1.DiscountGroupType = 1 -- discount = 1
			LEFT JOIN @DiscountGroup d3 ON s.PartyId = d3.PartyId AND s.IsCurrent = d3.IsCurrent AND d3.ProductId = s.ProductId AND d3.DiscountGroupType = 3 -- discount = 3
	WHERE	s.ProductId = 0
	
	-- Calculate Rebate
	UPDATE #Result 
	SET SportbookRebate = CASE WHEN (res.SportsbookFee - res.SportbookDiscount) < 0 THEN 0 ELSE (res.SportsbookFee - res.SportbookDiscount) * ISNULL(r.Rate, 0) END
	FROM	#Result res
	LEFT JOIN @DiscountGroup r ON res.PartyId = r.PartyId AND res.IsCurrent = r.IsCurrent AND r.ProductId = res.ProductId AND r.DiscountGroupType = 2 -- rebate = 2
	WHERE	res.ProductId = 0

	-- Sum other & discount/rebate
	CREATE TABLE #SumOther (
		IsCurrent		BIT,
		PartyId			INT,
		ProductId		INT,
		AmountToCompany	MONEY,
		NegativeAmount	MONEY,
		BetCount		INT,
		Turnover		MONEY,
		WinLoss			MONEY,
		BAComm			MONEY,
		AmountToBA		MONEY,
		Discount		MONEY
	)
	
	-- ********************************************************
	-- *** Calculate Other (!= SportBook) and Merge to #Result
	-- ********************************************************
	-- 31 exchange: include negative amount
	INSERT INTO #SumOther(IsCurrent, PartyId, ProductId, BetCount, Turnover, WinLoss, BAComm, AmountToBA, NegativeAmount, AmountToCompany, Discount)
	SELECT	t.IsCurrent,
			t.PartyId,
			t.ProductId,
			t.BetCount,
			t.Turnover,
			CASE WHEN t.ProductId = 31 THEN t.PComm ELSE 0 END + t.WinLoss,
			CASE WHEN t.ProductId = 3 THEN t.AComm ELSE 0 END BAComm,
			CASE WHEN t.ProductId = 3 THEN t.AmountToCompany ELSE 0 END AmountToBA,
			CASE WHEN t.ProductId = 31 THEN t.AmountToCompany ELSE 0 END NegativeAmount,
			CASE WHEN t.ProductId IN(3,31) OR t.AmountToCompany < 0 THEN 0 ELSE t.AmountToCompany END AmountToCompany,
			(CASE WHEN -t.WinLoss < 0 THEN 0 ELSE -t.WinLoss * ISNULL(d3.Rate, 0) END) + (CASE WHEN t.AmountToCompany < 0 THEN 0 ELSE t.AmountToCompany * ISNULL(d1.Rate, 0) END) AS Discount
	FROM	@SumByProducts t
	LEFT JOIN @DiscountGroup d1 ON t.PartyId = d1.PartyId AND t.IsCurrent = d1.IsCurrent AND d1.ProductId = t.ProductId AND d1.DiscountGroupType = 1 -- discount = 1
	LEFT JOIN @DiscountGroup d3 ON t.PartyId = d3.PartyId AND t.IsCurrent = d3.IsCurrent AND d3.ProductId = t.ProductId AND d3.DiscountGroupType = 3 -- discount = 3
	WHERE	t.ProductId != 0

	;WITH sumOther AS (
		SELECT	t.IsCurrent,
				t.PartyId,
				SUM(t.AmountToCompany) AmountToCompany,
				SUM(t.NegativeAmount) NegativeAmount,
				SUM(t.BetCount) BetCount,
				SUM(t.Turnover) Turnover,
				SUM(t.WinLoss) WinLoss,
				SUM(t.BAComm) BAComm,
				SUM(t.AmountToBA) AmountToBA,
				SUM(t.Discount) Discount,
				SUM(CASE WHEN (t.AmountToCompany - t.Discount) < 0 THEN 0 ELSE (t.AmountToCompany - t.Discount) * ISNULL(r.Rate, 0) END) Rebate
		FROM	#SumOther t
		LEFT JOIN @DiscountGroup r ON t.PartyId = r.PartyId AND t.IsCurrent = r.IsCurrent AND r.ProductId = t.ProductId AND r.DiscountGroupType = 2 -- rebate = 2
		GROUP BY t.IsCurrent, t.PartyId
	)
	MERGE	#Result r
	USING	sumOther s ON r.PartyId = s.PartyId AND r.IsCurrent = s.IsCurrent
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
		AverageBet	= CASE WHEN r.BetCount = 0 THEN r.Turnover ELSE (r.Turnover / r.BetCount) END,
		Margin		= CASE WHEN r.Turnover = 0 THEN r.WinLoss ELSE (-r.WinLoss/ r.Turnover) END,
		TotalFee	= ISNULL(r.SportsbookFee,0) + ISNULL(r.OthersFee,0) - ISNULL(r.SportbookDiscount,0) - ISNULL(r.OthersDiscount,0) - ISNULL(r.SportbookRebate,0) - ISNULL(r.OthersRebate,0)
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
			(CASE WHEN r.TotalFee > 0 THEN r.TotalFee ELSE 0 END) + ISNULL(r.NegativeAmount,0)		AS TotalLicensingFee,
			(CASE WHEN p.TotalFee > 0 THEN p.TotalFee ELSE 0 END) + ISNULL(p.NegativeAmount,0)		AS PreviousTotalLicensingFee
	FROM	#Result r
			LEFT JOIN (SELECT * FROM #Result WHERE IsCurrent = 0) p ON r.PartyId = p.PartyId
	WHERE	r.IsCurrent = 1 AND r.PartyId IN (SELECT pt.PartyId FROM @PartyIdTable pt WHERE IsSelected = 1)

	-- End region

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #Result
	-- End region
END
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_Detail] TO [bodbAdminNet]
GO
