/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template1]
	@PartyIds			VARCHAR(4000),
	@ProductID			INT,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20),
	@TimeZoneId			INT
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template1 - normal)
 * Revisions
	- 20210615@Danny: Initialize SP [#168387]
 */

BEGIN
	SET NOCOUNT ON

	DECLARE @ProductCode VARCHAR(50)
	DECLARE @BettypeIdList TABLE (BetTypeId INT)
	DECLARE @3rdRate TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME, MinAmount MONEY DEFAULT 0, MaxAmount MONEY DEFAULT 0, CurrencyId INT)
	
	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0)
	
	CREATE TABLE #ChargeRate (
		ChargeID		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY	DEFAULT 0
		,Rate3rd		MONEY	DEFAULT 0
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	CREATE TABLE #TempData (
		PartyID			INT,
		PartyName		NVARCHAR(100),
		ParentId		INT,
		ParentName		NVARCHAR(100),
		Winlostdate		DATETIME,
		CurrencyId		INT,
		Turnover		MONEY	DEFAULT 0,
		TotalTrans		INT		DEFAULT 0,
		CustomerWinLoss MONEY	DEFAULT 0,
		LicenseeWinloss MONEY	DEFAULT 0,
		LicensingFee	MONEY	DEFAULT 0,
		PayToSupplier	MONEY	DEFAULT 0,
		isDeposit		BIT,
		-- AGC
		ApplyValue		MONEY	DEFAULT 0
	)

	 -- Exchange
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, CASE WHEN ExchangeID = 51 THEN 'INH' 
										  WHEN ExchangeID = 92 THEN 'HID'  
										  ELSE Code END, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- ProductCode
	SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	-- Party list
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0
	
	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId

	-- Bettype List
	INSERT INTO @BettypeIdList (BetTypeId)
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode) la

	-- Handle chargeRate
	BEGIN
		IF @ProductID = 10 --AGC
		BEGIN
			INSERT INTO #ChargeRate(ChargeId, PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
			(
				SELECT	ChargeId, PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
				FROM	dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCode, 'OA', 1)
				WHERE	DI_Rate > 0
			)
		END
		ELSE IF @ProductID = 8
		BEGIN
			INSERT INTO #ChargeRate(ChargeId, PartyId, LicenseeId,ProductID, Rate, Fromdate, Todate, isDeposit)
			(
				SELECT ChargeId, PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate, isDeposit
				FROM dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1)
			
				UNION
			
				-- get Credit settings with rate = 0
				SELECT ci.ChargeID, p.PartyID, lb.LabelID AS LicenseeID, ci.ProductId, ci.Rate, 
					CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
					CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END, pd.IsDeposit
				FROM OAS_ChargeInfo ci WITH (NOLOCK)
				INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON ci.FromParty = p.PartyID AND ci.ChargeType != 2 AND p.PartyType = 1
				INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
				INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
				LEFT JOIN dbo.labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
				WHERE ci.Productid = 8 and ci.Rate = 0 AND ISNULL(pd.IsDeposit, 0) = 0 AND
					p.PartyID IN (SELECT VAL FROM strSplit(@PartyIDs, ','))	AND
					(	@FromDate BETWEEN ci.FromDate AND ci.ToDate
						OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
						OR ci.FromDate BETWEEN @FromDate AND @ToDate
						OR ci.ToDate BETWEEN @FromDate AND @ToDate)
			)
		END
		ELSE IF @ProductID = 22
		BEGIN
			INSERT INTO #ChargeRate(ChargeId, PartyId, ProductID, LicenseeId, Rate, Fromdate, Todate, IsDeposit)
			(
				SELECT c.ChargeID, c.PartyID, c.ProductID, c.LicenseeID, 
					CASE WHEN ISNULL(c.IsDeposit,0)=0 THEN 0 ELSE c.DI_Rate END,
					c.Fromdate, c.Todate, ISNULL(c.IsDeposit,0)
				FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1) c		
			)		
		END
		ELSE IF @ProductID = 23
		BEGIN
			INSERT INTO #ChargeRate (PartyId, LicenseeId, Rate3rd, ProductId, FromDate, ToDate, isDeposit)
			(
				SELECT PartyID, LicenseeID, DI_Rate, ProductID, Fromdate, Todate, isDeposit
				FROM dbo.LA_f_ChargeInfo(@PartyIDs,@FromDate,@ToDate,@ProductCode,'OA',1)
			)
		END
		ELSE IF @ProductID = 24
		BEGIN
			INSERT INTO #ChargeRate(ChargeId, PartyId, LicenseeId, ProductID, Rate, Rate3rd, Fromdate, Todate, IsDeposit)
			(
				SELECT a.ChargeID, a.PartyID, LicenseeID, a.ProductID, 
					CASE WHEN a.isDeposit = 0 THEN 0 ELSE DI_Rate END, 
					CASE WHEN a.isDeposit = 0 THEN a.DI_Rate ELSE b.Rate END AS Rate3rd, 
					a.Fromdate, a.Todate, a.IsDeposit
				FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1) a
					LEFT JOIN #PartyList p ON a.PartyID = p.PartyId
					LEFT JOIN #PartyList g ON p.ParentID = g.PartyID
					LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo b WITH (NOLOCK) ON p.ParentId = b.FromParty AND a.ProductID = b.ProductID 
						AND (a.Fromdate BETWEEN b.FromDate AND b.ToDate OR a.Todate BETWEEN b.FromDate AND b.ToDate )		
			)	
		END
		ELSE IF @ProductID = 27
		BEGIN
			INSERT INTO #ChargeRate(ChargeId, PartyId, ProductID, LicenseeId, Rate, Rate3rd, Fromdate, Todate, isDeposit)
			(
				SELECT c.ChargeID ,c.PartyID, c.ProductID, c.LicenseeID, c.DI_Rate,
					CASE WHEN ISNULL(c.IsDeposit,0)=0 THEN 0.01 ELSE 0.065 END,
					c.Fromdate, c.Todate, c.isDeposit
				FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'VS2', 'OA', 1) c

				UNION

				-- get Credit settings with rate = 0
				SELECT ci.ChargeID, p.PartyID, ci.ProductId, lb.LabelID AS LicenseeID, ci.Rate, 0.01 AS Rate3rd,
					CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate
						ELSE @FromDate END,
					CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate
						ELSE @ToDate END, pd.isDeposit
				FROM OAS_ChargeInfo ci
				INNER JOIN dbo.OAS_Party p ON ci.FromParty = p.PartyID	AND ci.ChargeType != 2 AND p.PartyType = 1
				INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
				INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
				LEFT JOIN dbo.labels lb(NOLOCK) ON p.OldRefID = lb.LicenseeID
				WHERE ci.Productid = @ProductID and ci.Rate = 0 AND ISNULL(pd.IsDeposit, 0) = 0 AND
					p.PartyID IN (	SELECT VAL
									FROM strSplit(@PartyIDs, ','))	AND
					(	@FromDate BETWEEN ci.FromDate AND ci.ToDate
						OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
						OR ci.FromDate BETWEEN @FromDate AND @ToDate
						OR ci.ToDate BETWEEN @FromDate AND @ToDate)
				)
		END
		ELSE IF @ProductID = 28
		BEGIN
			INSERT INTO #ChargeRate(ChargeId, PartyId, ProductID, LicenseeId, Rate, Rate3rd, Fromdate, Todate, isDeposit)
			(
				SELECT c.ChargeID, c.PartyID, c.ProductID, c.LicenseeID, c.DI_Rate,
					CASE 
						WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN 
														CASE WHEN c.PartyID IN (432, 346) THEN 0.02 ELSE 0.036  END --	@TianboPartyId INT = 432, @BobbetPartyId INT = 346
						WHEN c.PartyId = 14 OR ISNULL(c.IsDeposit,0)=0 OR @FromDate >= CAST('2018-8-1' AS DATETIME) THEN 0.03 
						ELSE 0.05 
					END,
					c.Fromdate, c.Todate, c.isDeposit
				FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'LT', 'OA', 1) c

				UNION

				-- get Credit settings with rate = 0
				SELECT ci.ChargeID, p.PartyID, ci.ProductId, lb.LabelID AS LicenseeID, ci.Rate, CASE WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN 0.036 ELSE 0.03 END AS Rate3rd,
					CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate
						ELSE @FromDate END,
					CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate
						ELSE @ToDate END, pd.IsDeposit
				FROM OAS_ChargeInfo ci
				INNER JOIN dbo.OAS_Party p ON ci.FromParty = p.PartyID	AND ci.ChargeType != 2 AND p.PartyType = 1
				INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
				INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
				LEFT JOIN dbo.labels lb(NOLOCK) ON p.OldRefID = lb.LicenseeID
				WHERE ci.Productid = @ProductID and ci.Rate = 0 AND ISNULL(pd.IsDeposit, 0) = 0 AND
					p.PartyID IN (	SELECT VAL
									FROM strSplit(@PartyIDs, ','))	AND
					(	@FromDate BETWEEN ci.FromDate AND ci.ToDate
						OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
						OR ci.FromDate BETWEEN @FromDate AND @ToDate
						OR ci.ToDate BETWEEN @FromDate AND @ToDate)
			)
		END
		ELSE IF @ProductID = 40
		BEGIN
			INSERT INTO @3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate)
			SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') r
			INNER JOIN #PartyList p on p.ParentId = r.PartyID

			INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
			SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, 
								CASE WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN 
														CASE WHEN c.PartyID IN (432, 346) THEN 0.02 ELSE 0.036  END  --@TianboPartyId INT = 432, @BobbetPartyId INT = 346
									 ELSE r.DI_Rate 
								END  AS Rate3rd, 
								c.Fromdate, c.Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, @ProductCode) c
			INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and r.ProductID = c.ProductID
			WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)
		END
		ELSE IF @ProductID = 65
		BEGIN
			INSERT INTO @3rdRate (PartyId, FromDate, ToDate, CurrencyId, MinAmount, MaxAmount, DI_Rate)
			SELECT DISTINCT p.PartyId, r.FromDate, r.ToDate, c.BaseCurrencyId, c.MinAmount - CASE WHEN c.MinAmount = 0 THEN 0 ELSE 1 END, c.MaxAmount, c.Rate
			FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') r
				INNER JOIN #PartyList p ON p.ParentId = r.PartyId
				INNER JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON r.ChargeId = c.ChargeId

			INSERT INTO #ChargeRate (ChargeId, PartyId, LicenseeId, IsDeposit, Rate, FromDate, ToDate)
			SELECT DISTINCT c.ChargeId, c.PartyId, c.LicenseeId, c.IsDeposit, c.DI_Rate, c.FromDate, c.ToDate
			FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, @ProductCode) c
			WHERE (c.IsDeposit = 0 AND c.DI_Rate = 0) OR (c.IsDeposit = 1 AND c.DI_Rate > 0)

		END
		ELSE IF @ProductID = 69
		BEGIN
			INSERT INTO @3rdRate (PartyId, FromDate, ToDate, DI_Rate)
			SELECT DISTINCT pl.PartyId, r.FromDate, r.ToDate, r.DI_Rate
			FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'BTC', 'OA') r
				INNER JOIN #PartyList pl ON r.PartyId = pl.ParentId

			-- ​#ChargeRate
			INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
			SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate,'SB') c
			LEFT JOIN @3rdRate r ON r.PartyID = c.PartyID and CASE WHEN r.ProductID = 69 THEN 0 ELSE  r.ProductID END = c.ProductID
			WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)

		END
		ELSE
		BEGIN
			-- Get 3rd Rate
			INSERT INTO @3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate)
			SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
			FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') r 
			INNER JOIN #PartyList p on p.ParentId = r.PartyID
	
			-- ​#ChargeRate
			INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
			SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate,@ProductCode) c
			INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and CASE WHEN r.ProductID = 69 THEN 0 ELSE  r.ProductID END = c.ProductID
			WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)
		END
	END
	
	-- Region: TempData 
	IF @TimeZoneId = 1 --GMT -4
	BEGIN
		IF @ProductID = 22
		BEGIN
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee, PayToSupplier, isDeposit)
			SELECT	ci.PartyId,
					b.rptDate,
					b.CurrencyId,
					SUM(b.Turnover) AS Turnover,
					SUM(b.BetCount) AS TotalTrans,
					SUM(b.WinLoss) AS CustomerWinLoss,
					- SUM(b.WinLoss) AS LicenseeWinloss,
					SUM(-b.WinLoss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
					SUM(-b.WinLoss * 
					CASE 
						WHEN ci.IsDeposit = 1 THEN (CASE WHEN bp.Bettype IS NOT NULL THEN 0.045 ELSE 0.035 END)
						ELSE (CASE WHEN bp.Bettype IS NOT NULL THEN 0.03 ELSE 0.02 END)
					END) AS PayToSupplier,
					ci.isDeposit
			FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
				LEFT JOIN bodb02.dbo.SportBettypeMatrix  bp WITH(NOLOCK) ON b.Bettype = bp.Bettype AND bp.ProductID = @ProductID AND bp.SubProduct = 'Blueprint'
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
				b.Status NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
				AND b.Bettype in (Select Bettype FROM LA_f_BettypeProductMapping(0,@ProductCode))
			GROUP BY b.rptDate, ci.PartyId, b.CurrencyId, ci.isDeposit
		END
		ELSE IF @ProductID = 23
		BEGIN 
			 ;WITH CalculateLicenseeWinLoss AS (
				SELECT r.PartyId,
					b.rptDate,
					b.CurrencyId,
					b.BetCount,
					b.Turnover,
					b.WinLoss,
					-(b.WinLoss + b.WinLossS + b.WinLossM + b.WinLossA + b.CommissionS) LicenseeWl,
					r.Rate3rd
				FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK) 
				INNER JOIN #ChargeRate r ON b.SiteID = r.LicenseeId AND b.rptDate BETWEEN r.FromDate AND r.ToDate
				WHERE b.Status NOT IN (-1, 101, 102, 103)
					AND b.Bettype in (Select Bettype FROM LA_f_BettypeProductMapping(0,@ProductCode))
					AND b.CustomerCategory NOT IN (27, 28)
					AND b.CurrencyId <> 20
					AND b.rptDate BETWEEN @FromDate AND @ToDate
			)
			INSERT INTO #TempData (PartyId, Winlostdate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier)
			SELECT PartyId,rptDate, CurrencyID, BetCount, Turnover, WinLoss, LicenseeWl , 0, LicenseeWl * Rate3rd
			FROM CalculateLicenseeWinLoss
		END
		ELSE
		BEGIN
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,isDeposit)
			SELECT ci.PartyId,
				b.rptDate		  AS Winlostdate,
				b.CurrencyId,
				SUM(b.Turnover)   AS Turnover,
				SUM(b.BetCount)	  AS TotalTrans,
				SUM(b.MemberWL)	  AS CustomerWinLoss,
				SUM(-b.MemberWL)  AS LicenseeWinloss,
				SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
				SUM(-b.MemberWL * ISNULL(ci.Rate3rd, 0))	AS PayToSupplier,
				ci.isDeposit
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate 
				AND b.StatusId NOT IN (-1, 101, 102, 103) 
				AND b.CurrencyId <> 20 
				AND b.CustomerCategory NOT IN (27,28)
				AND b.ProductID = @ProductID
			GROUP BY b.rptDate, ci.PartyId, b.CurrencyId, ci.isDeposit
		END
	END
	ELSE -- Another timezone
	BEGIN
		IF @ProductID = 22
		BEGIN
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee, PayToSupplier, isDeposit)
			SELECT	ci.PartyId,
					b.rptDate3rd,
					b.CurrencyId,
					SUM(b.Turnover) AS Turnover,
					SUM(b.BetCount) AS TotalTrans,
					SUM(b.WinLoss) AS CustomerWinLoss,
					- SUM(b.WinLoss) AS LicenseeWinloss,
					SUM(-b.WinLoss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
					SUM(-b.WinLoss * 
					CASE 
						WHEN ci.IsDeposit = 1 THEN (CASE WHEN bp.Bettype IS NOT NULL THEN 0.045 ELSE 0.035 END)
						ELSE (CASE WHEN bp.Bettype IS NOT NULL THEN 0.03 ELSE 0.02 END)
					END) AS PayToSupplier,
					ci.isDeposit
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate3rd BETWEEN ci.FromDate AND ci.ToDate
				LEFT JOIN bodb02.dbo.SportBettypeMatrix  bp WITH(NOLOCK) ON b.BettypeID = bp.Bettype AND bp.ProductID = @ProductID AND bp.SubProduct = 'Blueprint'
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE b.RptDate BETWEEN DATEADD(DAY, -1, @FromDate) AND DATEADD(DAY, 1, @ToDate)
					AND b.rptDate3rd BETWEEN @FromDate AND @ToDate 
					AND b.StatusID NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 
					AND b.BettypeID in (Select Bettype FROM LA_f_BettypeProductMapping(0,@ProductCode))
			GROUP BY b.rptDate3rd, ci.PartyId, b.CurrencyId, ci.isDeposit
		END
		ELSE 
		BEGIN
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,isDeposit)
			SELECT ci.PartyId,
				b.rptDate3rd		  AS Winlostdate,
				b.CurrencyId,
				SUM(b.Turnover)   AS Turnover,
				SUM(b.BetCount)	  AS TotalTrans,
				SUM(b.Winloss)	  AS CustomerWinLoss,
				SUM(-b.Winloss)  AS LicenseeWinloss,
				SUM(-b.Winloss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
				SUM(-b.Winloss * ISNULL(ci.Rate3rd, 0))	AS PayToSupplier,
				ci.isDeposit
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate3rd BETWEEN ci.FromDate AND ci.ToDate
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE b.RptDate BETWEEN DATEADD(DAY, -1, @FromDate) AND DATEADD(DAY, 1, @ToDate)
				AND b.rptDate3rd BETWEEN @FromDate AND @ToDate 
				AND b.StatusId NOT IN (-1, 101, 102, 103) 
				AND b.CurrencyId <> 20 
				AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
			GROUP BY b.rptDate3rd, ci.PartyId, b.CurrencyId, ci.isDeposit
		END
	END

	--- Special product
	BEGIN
		IF @ProductID = 10 -- AGC
		BEGIN
			DECLARE @ApplyRange TABLE (ParentId INT, SumApplyValue MONEY, ApplyRate MONEY)

			UPDATE td SET
				PartyName	= p.PartyName,
				ParentId	= pa.PartyId,
				ParentName	= pa.PartyName,
				ApplyValue	= CASE WHEN pa.PartyId = 1 -- group Oneworks
								THEN -td.CustomerWinLoss * ec.BaseCurrencyRate
								ELSE -td.CustomerWinLoss * eu.BaseCurrencyRate
							  END
			FROM #TempData td
			INNER JOIN #PartyList p ON td.PartyId = p.PartyID AND p.ParentId > 0		-- party
			INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId AND pa.ParentId = 0		-- billing group
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'CNY') ec ON td.CurrencyId = ec.ExchangeID AND ec.ExchangeDate = td.Winlostdate
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'USD') eu ON td.CurrencyId = eu.ExchangeID AND eu.ExchangeDate = td.Winlostdate

			INSERT INTO @ApplyRange (ParentId, SumApplyValue)
			SELECT ParentId, SUM(ApplyValue)
			FROM #TempData
			GROUP BY ParentId

			UPDATE @ApplyRange
			SET ApplyRate = CASE WHEN ParentId = 1 -- Oneworks
				THEN CASE WHEN SumApplyValue <= 15000000 THEN 0.08 ELSE 0.07 END
				ELSE CASE WHEN SumApplyValue <= 2500000 THEN 0.08 ELSE 0.07 END
			END

			UPDATE r
			SET r.PayToSupplier = a.ApplyRate * r.LicenseeWinLoss
			FROM #TempData r INNER JOIN @ApplyRange a ON r.ParentId = a.ParentId
		END

		IF @ProductID = 8
		BEGIN
			DECLARE	@12BetId		INT = 14,
					@CreditGroupId	INT = 999,
					@CN88PartyId	INT = (SELECT a.PartyID FROM dbo.OAS_Party a WITH(NOLOCK) WHERE a.PartyName='CN88'),
					@TianboPartyId	INT = 432,
					@BobbetPartyId	INT = 346

			UPDATE r
			SET r.PayToSupplier = r.LicenseeWinloss * (CASE 
														WHEN r.PartyId = @CN88PartyId THEN 0.015
														WHEN r.PartyId IN (@TianboPartyId, @BobbetPartyId) THEN 0.02
														WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN 0.036
														WHEN r.PartyId = 14 OR  r.isDeposit = 0 OR @FromDate >= CAST('2018-8-1' AS DATETIME) THEN 0.03 
														ELSE 0.05 
													END)
			FROM #TempData r 
		END

	END

	-- Region: Calculate result
	CREATE TABLE #Result (
		PartyId			INT,
		PartyName		VARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),
		WinLossDate		DATETIME,
		CurrencyId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		IsKeepNegativeAmount BIT
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, IsKeepNegativeAmount)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier, p.IsKeepNegativeAmount
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyId = p.PartyID
		INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId	

	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20)
	)

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20)
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC bodb_licensee.dbo.LA_SelBaseCurrency

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	IF @ProductID <> 65
	BEGIN
		WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
		BEGIN
			SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

			;WITH TotalByParty AS(
				SELECT  CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END ParentId, 
						td.PartyId, 
						td.IsKeepNegativeAmount,
						SUM(td.TotalTrans) TotalTrans,
						SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
						SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
						SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
						SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
						SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
				FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
				ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
				GROUP BY CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END, td.PartyId, td.IsKeepNegativeAmount
			)
			INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
			SELECT @tempCurrency,ParentId,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(CASE WHEN LicensingFee < 0 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END),
				SUM(PayToSupplier),
				SUM( CASE WHEN @ProductID = 23 THEN LicenseeWinLoss - PayToSupplier
						ELSE CASE WHEN LicensingFee < 0 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END - PayToSupplier END)
			FROM TotalByParty
			GROUP BY ParentId

			IF @ProductID = 27
			BEGIN
				UPDATE @Total
				SET PayToSupplier = 0
				WHERE PayToSupplier < 0
			END
		
			INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier, CompanyIncome)
			SELECT Currency,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(LicensingFee),
				SUM(PayToSupplier),
				SUM( CASE WHEN @ProductID = 23 THEN LicenseeWinLoss - PayToSupplier ELSE LicensingFee - PayToSupplier END)
			FROM @Total
			WHERE Currency = @tempCurrency
			GROUP BY Currency

			DELETE @BaseCurrencies WHERE [Name] = @tempCurrency
		END
		-- Select data by Parties
		SELECT 
			r.PartyId,
			r.PartyName,
			CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId,
			CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END ParentName,
			r.WinLossDate,
			e.CurrencyCode AS CurrencyName,
			-- Select by origin currency
			r.TotalTrans,
			r.Turnover AS TurnoverOriginal,
			CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
			CAST((r.LicenseeWinLoss) AS MONEY) AS LicenseeWinLossOriginal,
			CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
			CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
			r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
			-- Select by base currency
			r.Turnover * e.Rate AS Turnover,
			CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
			CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
			CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
			CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
			CASE WHEN @ProductID =23 THEN CAST(((r.LicenseeWinLoss - r.PayToSupplier) * e.Rate)AS MONEY)
				 ELSE CAST(((r.LicensingFee - r.PayToSupplier) * e.Rate)AS MONEY) END AS CompanyIncome
		FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	
		-- Select Grand Total
		SELECT 	CurrencyName,
				TotalTrans		,
				Turnover		,
				CustomerWinLoss	,
				LicenseeWinLoss	,
				LicensingFee	,
				PayToSupplier	,
				CompanyIncome	 
		FROM @GrandTotal
	
		-- Total
		SELECT 
			PartyId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,
			LicenseeWinLoss,
			LicensingFee,
			PayToSupplier,
			CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	-- End Region
	END
	ELSE
	BEGIN
		DECLARE @BaseCurrencyRate TABLE (ExchangeId INT, ExchangeDate DATETIME, BaseCurrencyName VARCHAR(20), Rate FLOAT)
		INSERT INTO @BaseCurrencyRate (ExchangeId, ExchangeDate, BaseCurrencyName, Rate)
		SELECT e.ExchangeId, e.ExchangeDate, bc.Name, e.BaseCurrencyRate
		FROM @BaseCurrencies bc
			CROSS APPLY bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, bc.Name) e

		;WITH CTE_SumByParty AS (
			SELECT CASE WHEN  r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId, e.BaseCurrencyName,
				SUM(r.TotalTrans)				AS TotalTrans,
				SUM(r.Turnover * e.Rate)		AS Turnover,
				SUM(r.CustomerWinLoss * e.Rate) AS CustomerWinLoss,
				SUM(r.LicenseeWinLoss * e.Rate) AS LicenseeWinLoss,
				SUM(r.LicensingFee * e.Rate)	AS LicensingFee
			FROM #Result r
				INNER JOIN @BaseCurrencyRate e ON e.ExchangeId = r.CurrencyId AND e.ExchangeDate = r.WinLossDate
			GROUP BY CASE WHEN  r.PartyId = 14 THEN 14 ELSE r.ParentId END, r.PartyId, e.BaseCurrencyName
		)
		INSERT INTO @Total (Currency, PartyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee)
		SELECT BaseCurrencyName, ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END)
		FROM CTE_SumByParty
		GROUP BY BaseCurrencyName, ParentId

		-- Total by Party
		DECLARE @TotalByParty TABLE
		(
			PartyId			INT,
			PartyName		VARCHAR(100),
			ParentId		INT,
			TotalTrans		INT,
			Turnover		MONEY,
			CustomerWinLoss	MONEY,
			LicenseeWinLoss	MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY
		)
		INSERT INTO @TotalByParty (PartyId, PartyName, ParentId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee)
		SELECT r.PartyId, r.PartyName, r.ParentId,
			SUM(r.TotalTrans),
			SUM(r.Turnover * e.Rate),
			SUM(r.CustomerWinLoss * e.Rate),
			SUM(r.LicenseeWinLoss * e.Rate),
			CASE WHEN SUM(r.LicensingFee * e.Rate) > 0 THEN SUM(r.LicensingFee * e.Rate) ELSE 0 END
		FROM #Result r
			INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
		GROUP BY r.PartyId, r.PartyName, r.ParentId

		-- Update PayToSupplier base on Licensee WL
		DECLARE @CurrencyId INT, @CurrencyName VARCHAR(100)
		SELECT TOP 1 @CurrencyId = CurrencyId FROM @3rdRate WHERE CurrencyId IS NOT NULL

		IF @CurrencyId IS NULL
			SELECT @CurrencyId = ID FROM @BaseCurrencies WHERE Name = @BaseCurrencyName
	
		SELECT @CurrencyName = Code FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE ExchangeId = @CurrencyId

		UPDATE @3rdRate SET CurrencyId = @CurrencyId WHERE CurrencyId IS NULL
		UPDATE @3rdRate SET MinAmount = 0, MaxAmount = 10000000000000 WHERE MinAmount IS NULL OR MaxAmount IS NULL

		-- Detail
		;WITH CTE_Sum AS (
			SELECT t.PartyId, t.CurrencyId, t.WinLossDate, e.BaseCurrencyRate, SUM(t.LicenseeWinloss * e.BaseCurrencyRate) AS LicenseeWinloss
			FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @CurrencyName) e
				INNER JOIN #Result t ON t.CurrencyId = e.ExchangeId AND e.ExchangeDate = t.WinLossDate
			GROUP BY t.PartyId, t.CurrencyId, t.WinLossDate, e.BaseCurrencyRate
		), CTE_3rdRate AS (
			SELECT s.PartyId, s.CurrencyId, s.WinLossDate, SUM(CASE WHEN s.BaseCurrencyRate = 0 THEN 0 ELSE (CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.DI_Rate / s.BaseCurrencyRate END) AS PayToSupplier
			FROM CTE_Sum s
				INNER JOIN @3rdRate r ON s.PartyId = r.PartyId AND (s.LicenseeWinloss > r.MinAmount OR (s.LicenseeWinloss < 0 AND r.MinAmount = 0))
			GROUP BY s.PartyId, s.CurrencyId, s.WinLossDate
		)
		UPDATE t
		SET t.PayToSupplier = ISNULL(r.PayToSupplier, 0)
		FROM #Result t
			LEFT JOIN CTE_3rdRate r ON t.PartyId = r.PartyId AND t.CurrencyId = r.CurrencyId AND t.WinLossDate = r.WinLossDate

		-- TotalByParty
		;WITH CTE_Sum AS (
			SELECT r.PartyId, SUM(r.LicenseeWinloss * e.Rate) AS LicenseeWinloss
			FROM #Result r
				INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
			GROUP BY r.PartyId
		), CTE_3rdRate AS (
			SELECT r.PartyId, r.MinAmount * e.Rate AS MinAmount, r.MaxAmount * e.Rate AS MaxAmount, r.DI_Rate
			FROM @3rdRate r
				INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND e.ExchangeDate = @ToDate
		), CTE_Final AS (
			SELECT s.PartyId, SUM((CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.DI_Rate) AS PayToSupplier
			FROM CTE_Sum s
				INNER JOIN CTE_3rdRate r ON s.PartyId = r.PartyId AND (s.LicenseeWinloss > r.MinAmount OR (s.LicenseeWinloss < 0 AND r.MinAmount = 0))
			GROUP BY s.PartyId
		)
		UPDATE t
		SET t.PayToSupplier = ISNULL(f.PayToSupplier, 0)
		FROM @TotalByParty t
			LEFT JOIN CTE_Final f ON t.PartyId = f.PartyId

		-- Total
		;WITH CTE_Sum AS (
			SELECT r.PartyId, CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId, br.BaseCurrencyName, SUM(r.LicenseeWinloss * br.Rate) AS LicenseeWinloss
			FROM #Result r
				INNER JOIN @BaseCurrencyRate br ON r.CurrencyId = br.ExchangeId AND r.WinLossDate = br.ExchangeDate
			GROUP BY r.PartyId, CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END, br.BaseCurrencyName
		), CTE_3rdRate AS (
			SELECT r.PartyId, br.BaseCurrencyName, r.MinAmount * br.Rate AS MinAmount, r.MaxAmount * br.Rate AS MaxAmount, r.DI_Rate
			FROM @3rdRate r
				INNER JOIN @BaseCurrencyRate br ON r.CurrencyId = br.ExchangeId AND br.ExchangeDate = @ToDate
		), CTE_Final AS (
			SELECT s.ParentId, s.BaseCurrencyName, SUM((CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.DI_Rate) AS PayToSupplier
			FROM CTE_Sum s
				INNER JOIN CTE_3rdRate r ON s.PartyId = r.PartyId AND s.BaseCurrencyName = r.BaseCurrencyName AND (s.LicenseeWinloss > r.MinAmount OR (s.LicenseeWinloss < 0 AND r.MinAmount = 0))
			GROUP BY s.ParentId, s.BaseCurrencyName
		)
		UPDATE t
		SET t.PayToSupplier = ISNULL(f.PayToSupplier, 0)
		FROM @Total t
			LEFT JOIN CTE_Final f ON t.PartyId = f.ParentId AND t.Currency = f.BaseCurrencyName

		-- Return data
		BEGIN
			-- Detail by Parties
			SELECT 
				r.PartyId,
				r.PartyName,
				CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId,
				CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END ParentName,
				r.WinLossDate,
				e.CurrencyCode AS CurrencyName,
				r.TotalTrans,
				-- Original Currency
				r.Turnover			AS TurnoverOriginal,
				r.CustomerWinLoss	AS CustomerWinLossOriginal,
				r.LicenseeWinLoss	AS LicenseeWinLossOriginal,
				r.LicensingFee		AS LicensingFeeOriginal,
				r.PayToSupplier		AS PayToSupplierOriginal,
				r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
				-- Base Currency
				CONVERT(MONEY, r.Turnover * e.Rate)			AS Turnover,
				CONVERT(MONEY, r.CustomerWinLoss * e.Rate)	AS CustomerWinLoss,
				CONVERT(MONEY, r.LicenseeWinLoss * e.Rate)	AS LicenseeWinLoss,
				CONVERT(MONEY, r.LicensingFee * e.Rate)		AS LicensingFee,
				CONVERT(MONEY, r.PayToSupplier * e.Rate)	AS PayToSupplier,
				CONVERT(MONEY, (r.LicensingFee - r.PayToSupplier) * e.Rate) AS CompanyIncome
			FROM #Result r
				INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
	
			-- Grand Total
			SELECT
				Currency				AS CurrencyName
				,SUM(TotalTrans)		AS TotalTrans
				,SUM(Turnover)			AS Turnover
				,SUM(CustomerWinLoss)	AS CustomerWinLoss
				,SUM(LicenseeWinLoss)	AS LicenseeWinLoss
				,SUM(LicensingFee)		AS LicensingFee
				,SUM(PayToSupplier)		AS PayToSupplier
				,SUM(LicensingFee - PayToSupplier) AS CompanyIncome
			FROM @Total
			GROUP BY Currency

			-- Total by Party
			SELECT PartyId, PartyName, CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, LicensingFee - PayToSupplier AS CompanyIncome
			FROM @TotalByParty
	
			-- Total
			SELECT
				PartyId,
				TotalTrans,
				Turnover,
				CustomerWinLoss,
				LicenseeWinLoss,
				LicensingFee,
				PayToSupplier,
				LicensingFee - PayToSupplier AS CompanyIncome
			FROM @Total
			WHERE Currency = @BaseCurrencyName
		END

	END

	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
	DROP TABLE  #Result
END
GO