/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceWaiveGet] 
	@FromDate		DATE,
	@ToDate			DATE,
	@PartyId		INT,
	@ProductCode	VARCHAR(100) = 'SB'	  /* Default is Sportbook and currently we use this SP for SB only */
AS
/*	Header:
	Created: 2017-05-09 - @Scofield.Huynh
	DB: DBLIC.bodb_Licensee   
	Revisions: 
		+ 2017-05-09 @Scofield.Huynh: Create [#76132]
		- 20171220@Parsons: increase length for variables [#88197]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20201202@Mason: Change request Odds Spread [#142345]
		- 20210314@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
		- 20210408@Parsons: Remove redundant linked server [#FeatureID 152089]
*/
BEGIN
	SET NOCOUNT ON
	
	-- Region: Caculate FirstDate of month, LastDate of month, DaysInMonth
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1
	-- End region

	-- Region: Get Base Currency for Party
	DECLARE @BaseCurrencyId INT = 6 -- default is EUR

	SELECT TOP 1 @BaseCurrencyId = BaseCurrencyId
	FROM OAS_PartyBaseCurrency WITH(NOLOCK)
	WHERE PartyID = @PartyId AND FromDate <= @ToDate AND ToDate >= @FromDate

	DECLARE @BaseCurrencyTable AS TABLE(Id INT, Name VARCHAR(10))
	INSERT	INTO @BaseCurrencyTable(Id,Name)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
	DECLARE @BaseCurrencyName VARCHAR(5)
	SELECT	@BaseCurrencyName = Name
	FROM	@BaseCurrencyTable bct
	WHERE	@BaseCurrencyId = bct.Id
	-- End region
	
	-- Region: Party Group Assignment
	DECLARE @PartyGroup AS TABLE (PartyId INT)
	INSERT	INTO @PartyGroup(PartyId)
	(
		SELECT	PartyId 
		FROM	dbo.LA_PartyGroupAssignment WITH(NOLOCK)
		WHERE	PartyGroupId IN (	SELECT	PartyGroupId 
									FROM	dbo.LA_PartyGroupAssignment WITH(NOLOCK)
									WHERE	PartyId = @PartyId)
	)
	
	IF (SELECT COUNT(*) FROM @PartyGroup) = 0 -- Party dont have Party Group.
	BEGIN 
		INSERT INTO @PartyGroup(PartyId) VALUES(@PartyId)
	END
	-- End region

	-- Region: Get party charge rate info
	DECLARE	@PartyIdString VARCHAR(4000)
	SELECT	@PartyIdString = COALESCE(@PartyIdString + ', ', '') + CONVERT(VARCHAR(10), PartyId)
	FROM	@PartyGroup 
	
	DECLARE @PartyChargeInfo AS TABLE (
			ChargeId	INT,
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			BettypeRef  INT,
			Rate		MONEY,
			TypeId		SMALLINT,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(ChargeId, PartyId, LicenseeId, ProductID, BettypeRef, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT ChargeId, PartyID, LicenseeID, ProductID, Bettype, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIdString, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId NOT IN (1, 15) --exclude RB, CB
	)
	-- End region

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange ( 
			ExchangeDate	DATE, 
			ExchangeID		INT, 
			CurrencyCode	VARCHAR(10), 
			Rate			FLOAT)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)	
	-- End region

	-- Region: Select MinFee, Waive
	DECLARE @MinFeeGroup TABLE(
			FeeType			TINYINT,
			PartyId			INT,
			ProductId		INT,
			CurrencyId		INT,
			FeeAmount		MONEY,		
			FromDate		DATETIME,
			ToDate			DATETIME,
			MinFeeProrate	MONEY,
			MinFeeAmount	MONEY,
			IsApplyMinFee	BIT)
	
	INSERT INTO @MinFeeGroup(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
	(
		SELECT	mf.FeeTypeId, 
				mf.PartyId,
				mf.ProductId, 
				mf.CurrencyId,
				mf.FeeAmount,
				CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
				CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate
		FROM	dbo.LA_MinFee mf WITH(NOLOCK)
		WHERE   ((mf.FeeTypeId = 1 AND mf.CurrencyId = @BaseCurrencyId ) 
					OR mf.FeeTypeId = 2 AND EXISTS (SELECT	PartyId 
													FROM	dbo.LA_MinFee m WITH(NOLOCK)
													WHERE	m.FeeTypeId = 1 
															AND m.PartyId = mf.PartyId
															AND m.ProductId = mf.ProductId
															AND m.CurrencyId = @BaseCurrencyId
															AND ((m.FromDate BETWEEN @FromDate AND @ToDate) 
																OR (m.ToDate BETWEEN @FromDate AND @ToDate) 
																OR (m.FromDate<@FromDate AND @ToDate < m.ToDate)
															)
													)
				)					
				AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
				AND ((mf.FromDate BETWEEN @FromDate AND @ToDate) 
					OR (mf.ToDate BETWEEN @FromDate AND @ToDate) 
					OR (mf.FromDate<@FromDate AND @ToDate < mf.ToDate)
				)
				AND (mf.PartyId = @PartyId OR mf.PartyId IN (SELECT PartyId FROM @PartyGroup))
	)
	
	DELETE	FROM @MinFeeGroup
	WHERE	ProductID NOT IN (SELECT ProductId FROM @MinFeeGroup WHERE [@MinFeeGroup].PartyId = @PartyId)	
			OR (FeeType = 2 AND (FromDate > ToDate))

	-- Region: Get Amount by Product
	DECLARE @OddsSpreadCost_BetType INT = 999
	CREATE	TABLE #TempData (
			LicenseeId		INT, 
			PartyId			INT, 
			rptDate			DATETIME, 
			CurrencyId		INT, 
			WinLoss			MONEY, 
			ProductId		TINYINT,
			BettypeRef		INT, 
			AmountToCompany MONEY,
			IsApplyMinFee	BIT,
			OddsSpreadCost	MONEY)
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,WinLoss,ProductId,BettypeRef,OddsSpreadCost)
	(
		SELECT	b.SiteID,
				p.PartyId, 
				b.rptDate, 
				b.CurrencyID, 
				SUM(CASE WHEN b.Bettype = @OddsSpreadCost_BetType THEN 0 ELSE (ISNULL(b.MemberWL, 0)) END) Winloss, 
				p.ProductId,
				r.BettypeRef,
				SUM(CASE WHEN b.Bettype = @OddsSpreadCost_BetType THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) OddsSpreadCost
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				LEFT JOIN dbo.Sport_Bettype_Reference r ON b.Bettype = r.Bettype
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.Bettype = -1 OR b.Bettype = @OddsSpreadCost_BetType OR r.BettypeRef = p.BettypeRef)
													AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (-1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914) -- exclude BT and CO
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, r.BettypeRef
	)
	
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId, ProductId)

	UPDATE	#TempData
	SET		AmountToCompany = (-td.WinLoss * ISNULL(cr.Rate, p.Rate) + td.OddsSpreadCost) * e.Rate
	FROM	#TempData td 
			INNER JOIN @PartyChargeInfo p 
				ON td.LicenseeId = p.LicenseeId 
				AND ((td.ProductId = p.ProductID AND td.ProductId NOT IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub WITH(NOLOCK)))
						OR 
					(td.ProductId = p.ProductID AND td.BettypeRef = p.BettypeRef AND td.ProductId IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub WITH(NOLOCK))))
				AND td.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN #Exchange e ON td.rptDate = e.ExchangeDate AND td.CurrencyId = e.ExchangeID
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeId AND td.CurrencyID = cr.CurrencyId

	UPDATE  t
	SET		t.IsApplyMinFee = 0
	FROM	#TempData t INNER JOIN @MinFeeGroup m ON t.rptDate BETWEEN m.FromDate AND m.ToDate
			AND t.ProductId = m.ProductId
			AND t.PartyId = m.PartyId
	WHERE	m.FeeType=2
	-- End region	

	-- Region: Calculate min fee prorate (fee amount in month - waived amount (*)
	UPDATE	amf
	SET		MinFeeProrate = ((	SELECT	TOP 1 mfg.FeeAmount
								FROM	@MinFeeGroup mfg
								WHERE	mfg.FeeType = 1
										AND mfg.PartyId = amf.PartyId
										AND mfg.ProductId = amf.ProductId)
							/ @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)	
	FROM	@MinFeeGroup amf
	WHERE	FeeType = 2
	
	UPDATE	amf
	SET		amf.MinFeeProrate = ROUND((	amf.FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1) - 
										ISNULL((SELECT	SUM(f.MinFeeProrate)							
												FROM	@MinFeeGroup f
												WHERE	f.FeeType = 2
														AND amf.PartyId = f.PartyId
														AND amf.ProductId = f.ProductId), 0), 2),
			amf.MinFeeAmount =  ISNULL((SELECT	SUM(td.AmountToCompany)		-- amount not in waived period					
										FROM	#TempData td 
										WHERE	amf.PartyId = td.PartyId
												AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
												AND td.IsApplyMinFee IS NULL
												AND amf.ProductId = td.ProductId), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1
	-- End region

	-- Region: Sum min fee amount
	DECLARE @TotalMinFees TABLE(
		ProductId			INT,
		TotalMinFee			MONEY,
		TotalMinFeeAmount	MONEY
	)
	
	INSERT	INTO @TotalMinFees(ProductId, TotalMinFee)
	SELECT	mf.ProductId,
			SUM(MinFeeProrate)
	FROM	@MinFeeGroup mf
	WHERE	mf.FeeType = 1
	GROUP BY mf.ProductId
	
	UPDATE	t
	SET		TotalMinFeeAmount = ISNULL((	SELECT	SUM(mf.MinFeeAmount)
											FROM	@MinFeeGroup mf
											WHERE	mf.MinFeeAmount > 0
													AND FeeType = 1
													AND mf.ProductId = t.ProductId), 0)
	FROM	@TotalMinFees t
	-- End region

	-- Region: Calculate IsApplyMinFee
	UPDATE	amf
	SET		amf.IsApplyMinFee = CASE WHEN (t.TotalMinFeeAmount < t.TotalMinFee) AND (amf.MinFeeAmount < amf.MinFeeProrate) THEN 1 ELSE 0 END
	FROM	@MinFeeGroup amf INNER JOIN @TotalMinFees t ON amf.ProductId = t.ProductId
	WHERE	amf.FeeType = 1	
	-- End region

	-- Region: Manipulate Result
	DECLARE @Result TABLE(
		FromDate			DATETIME,
		ToDate				DATETIME,
		CurrencyName		NVARCHAR(20),
		MinFeeAmount		MONEY,
		MinFeeProrate		MONEY,
		MinFeeProrateTotal	MONEY,
		NumberOfDays		FLOAT,
		DaysInMonth			INT,
		IsWaived			BIT DEFAULT 0)

	-- Split waive range and non-waive range
	IF ((SELECT COUNT(*) FROM @MinFeeGroup WHERE FeeType = 2 AND PartyId = @PartyId) > 0)
	BEGIN
		INSERT INTO @Result(FromDate, ToDate, IsWaived)
		SELECT FromDate, ToDate, 1
		FROM @MinFeeGroup WHERE FeeType = 2 AND PartyId = @PartyId

		IF (SELECT MIN(FromDate) FROM @Result ) > @FromDate
		INSERT INTO @Result (FromDate, ToDate) VALUES(@FromDate, DATEADD(DAY,-1,(SELECT MIN(FromDate) FROM @Result )))

		IF (SELECT MAX(ToDate) FROM @Result ) < @ToDate
		INSERT INTO @Result (FromDate, ToDate) VALUES(DATEADD(DAY,1,(SELECT MAX(ToDate) FROM @Result )), @ToDate)
		
		;WITH OrderedPeriods AS (
			SELECT *, ROW_NUMBER() OVER(ORDER BY FromDate) period FROM @Result
		)
		INSERT INTO @Result(FromDate, ToDate)
		SELECT DATEADD(DAY,1,a.ToDate), DATEADD(DAY,-1,(SELECT b.FromDate FROM OrderedPeriods b WHERE b.period=(a.period+1)))
		FROM OrderedPeriods a
		WHERE DATEADD(DAY,1,a.ToDate) < (SELECT b.FromDate FROM OrderedPeriods b WHERE b.period=(a.period+1))
	END
	ELSE IF ((SELECT COUNT(*) FROM @MinFeeGroup WHERE PartyId = @PartyId AND IsApplyMinFee = 1) > 0)
	BEGIN
		INSERT INTO @Result(FromDate, ToDate, IsWaived)
		SELECT FromDate, ToDate, 0
		FROM @MinFeeGroup WHERE PartyId = @PartyId AND IsApplyMinFee = 1
	END

	UPDATE @Result
	SET CurrencyName = @BaseCurrencyName, 
		MinFeeAmount = (SELECT TOP 1 FeeAmount FROM @MinFeeGroup WHERE FeeType = 1 AND PartyId = @PartyId),
		MinFeeProrateTotal = (SELECT TOP 1 MinFeeProrate FROM @MinFeeGroup WHERE FeeType = 1 AND PartyId = @PartyId AND IsApplyMinFee = 1),
		NumberOfDays = (DATEDIFF(DAY, FromDate, ToDate) + 1),
		DaysInMonth = @DaysInMonth
	WHERE IsWaived = 0

	UPDATE @Result
	SET MinFeeProrate = ISNULL(MinFeeProrateTotal,0) * (NumberOfDays/(SELECT SUM(NumberOfDays) FROM @Result))
	-- End region

	-- Region: Get result
	SELECT FromDate, ToDate, CurrencyName, MinFeeAmount, MinFeeProrate, NumberOfDays, DaysInMonth, IsWaived
	FROM @Result
	WHERE IsWaived = 1 OR NumberOfDays < DaysInMonth
	ORDER BY FromDate
	-- End region

	DROP TABLE #Exchange
	DROP TABLE #TempData
END		
GO