/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template5]
	@PartyIds			VARCHAR(MAX)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
	,@TimeZoneId		INT
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template5 - Template for PP including some specific info such as: Promotion, Jackpot)
 * Revisions
	- 20210615@Danny: Initialize SP [#168387]
	- 20221031@Danny: PP Tournament for Credit licensee [RedmineID: #178619]
	- 20220927@Danny: Fix issue BetCount and Licensing Fee PP GMT-4 are incorrect [#176775]
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
	- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
	- 20241016@Danny: Extend parameter data length [RemineID: #212252]
 */

BEGIN
	SET NOCOUNT ON 
	DECLARE @ProductCode VARCHAR(50)
	SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	DECLARE		@Contribution INT,
				@JackpotPrize INT

	DECLARE 	@PrizeBettype TABLE (bettype SMALLINT)
				
	SELECT @Contribution = Bettype FROM LA_f_GroupBettype() WHERE TypeId = 2 AND ProductId = @ProductID
	SELECT @JackpotPrize = Bettype FROM LA_f_GroupBettype() WHERE TypeId = 3 AND ProductId = @ProductID

	INSERT INTO @PrizeBettype(bettype) SELECT Bettype FROM LA_f_GroupBettype() WHERE TypeId = 4 AND ProductId = @ProductID

	DECLARE @BettypeIdList TABLE (BetTypeId INT)
	INSERT INTO @BettypeIdList (BetTypeId)
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode) la

	-- Region: Party List
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT, ParentName VARCHAR(100), IsKeepNegativeAmount BIT DEFAULT 0)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel

	UPDATE @PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0
	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM @PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId
	-- End region

	UPDATE p
	SET p.ParentName = pa.PartyName
	FROM @PartyList p
	INNER JOIN @PartyList pa ON pa.ParentId = 0 AND p.ParentId = pa.PartyId

	DECLARE @f_date3rd DATE = @FromDate
	DECLARE @t_date3rd DATE = @ToDate
	DECLARE @f_date DATE = DATEADD(DAY, -1, @FromDate)
	DECLARE @t_date DATE = DATEADD(DAY, 1, @ToDate)

	-- Region: Exchange
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(65),
		Rate			FLOAT
	)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH' 
															WHEN ExchangeID = 92 THEN 'HID' 
															ELSE Code 
														END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End Region

	DECLARE @BaseCurrencies TABLE(Id INT, Name VARCHAR(20), IsApply BIT)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	-- Region: Charge Info	
	DECLARE @ChargeInfos AS TABLE (
		ChargeId	INT,
		PartyId		INT,
		LicenseeId	INT,
		isDeposit	BIT,
		ProductID	INT,
		Rate		MONEY,
		Rate3rd		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME)	


	-- get licenseeFee's charge rate
	INSERT INTO @ChargeInfos(ChargeId, PartyId, ProductID, LicenseeId, isDeposit, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT c.ChargeID, c.PartyID, c.ProductID, c.LicenseeID, ISNULL(c.isDeposit, 0) AS isDeposit,
			CASE WHEN ISNULL(c.isDeposit, 0) = 1 THEN c.DI_Rate ELSE 0 END,
			c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1) c		
	)
	-- End region

	DELETE p
	FROM @PartyList p
	WHERE NOT EXISTS (SELECT 1 FROM @ChargeInfos ci WHERE ci.PartyId = p.PartyId)

	-- Region: update Rate3rd for Deposit's charge rate
	UPDATE ci
	SET Rate3rd = CI3rd.DI_Rate
	FROM @ChargeInfos ci
	INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	INNER JOIN LA_f_ChargeInfo3rd (@FromDate, @ToDate, @ProductCode, 'OA') CI3rd ON p.ParentId = CI3rd.PartyID AND ci.ProductID = CI3rd.ProductID
	WHERE ISNULL(CI3rd.IsDeposit, 0) = 1
	-- Endregion

	-- Get data
	BEGIN
		-- Region: #Result
		CREATE TABLE #Result_PP (
			PartyID		INT,
			PartyName	NVARCHAR(100),
			ParentId	INT,
			ParentName	VARCHAR(100),
			Winlossdate DATETIME,
			CurrencyId	INT,
			Turnover	MONEY,
			TotalTrans	INT,
			WinPrizeAmount	MONEY,
			JackpotPrize	MONEY,
			LicenseeContribution	MONEY,
			FullContribution		MONEY,
			CustomerWinLoss MONEY,
			LicenseeWinloss MONEY,
			LicensingFee	MONEY,
			LicenseeChargeRate	MONEY,
			PayToSupplier	MONEY,
			IsKeepNegativeAmount BIT
			)

		DECLARE @GrandTotal_PP TABLE (
			CurrencyName	VARCHAR(20),
			TotalTrans		INT,
			Turnover		MONEY,
			WinPrizeAmount	MONEY,
			JackpotPrize	MONEY,
			LicenseeContribution	MONEY,
			FullContribution		MONEY,
			CustomerWinLoss	MONEY,
			LicenseeWinLoss	MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY,
			CompanyIncome	MONEY
		)

	
		DECLARE @Total_PP TABLE (
			PartyId			INT,
			TotalTrans		INT,
			Turnover		MONEY,
			WinPrizeAmount	MONEY,
			JackpotPrize	MONEY,
			LicenseeContribution	MONEY,
			FullContribution		MONEY,
			CustomerWinLoss	MONEY,
			LicenseeWinLoss	MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY,
			CompanyIncome	MONEY,
			Currency		VARCHAR(20)
		)
	
		-- Calculate for deposit
		IF @TimeZoneId = 1 
		BEGIN
			;WITH cte_WinLossData AS
			(
				SELECT ci.PartyId,
					b.RptDate,
					b.CurrencyId,
					b.SiteId,
					SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.Turnover END) AS Turnover,
					SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL  THEN 0 ELSE b.BetCount END) AS TotalTrans,
					SUM(CASE WHEN pb.bettype IS NOT NULL  THEN b.Winloss ELSE 0 END) AS WinPrizeAmount,
					SUM(CASE WHEN b.BetTypeId = @JackpotPrize THEN b.Winloss ELSE 0 END) AS JackpotPrize,
					SUM(CASE WHEN b.BetTypeId = @Contribution THEN -b.AWinloss ELSE 0 END) AS LicenseeContribution,
					SUM(CASE WHEN b.BetTypeId = @Contribution THEN ProgressiveContribution ELSE 0 END) AS FullContribution,
					SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL  THEN 0 ELSE b.Winloss END) AS CustomerWinLoss,
					SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL  THEN 0 ELSE -b.Winloss END) AS LicenseeWinloss
				FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
					INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate BETWEEN ci.FromDate AND ci.ToDate
					INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
					LEFT JOIN @PrizeBettype pb ON b.BetTypeId = pb.bettype
				WHERE b.RptDate BETWEEN @f_date3rd AND @t_date3rd
					AND b.RptDate3rd BETWEEN @f_date AND @t_date
					AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
					AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
					AND ci.isDeposit = 1
				GROUP BY b.RptDate, ci.PartyId, b.CurrencyId, b.SiteId
			)
			INSERT INTO #Result_PP (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,WinPrizeAmount,JackpotPrize,LicenseeContribution,FullContribution,CustomerWinLoss,LicenseeWinloss,LicensingFee,LicenseeChargeRate,PayToSupplier, IsKeepNegativeAmount)
			SELECT ci.PartyId,
				p.PartyName,
				p.ParentId,
				p.ParentName,
				b.RptDate,
				b.CurrencyId,
				SUM(Turnover),
				SUM(TotalTrans),
				SUM(WinPrizeAmount),
				SUM(JackpotPrize),
				SUM(LicenseeContribution),
				SUM(FullContribution),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinloss),
				SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate) + LicenseeContribution - JackpotPrize - WinPrizeAmount) AS LicensingFee,
				SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
				SUM((LicenseeWinloss - FullContribution) * ci.Rate3rd) AS PayToSupplier,
				p.IsKeepNegativeAmount
			FROM cte_WinLossData b
				INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate BETWEEN ci.FromDate AND ci.ToDate
				INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeId AND cr.CurrencyID = b.CurrencyId
			GROUP BY b.RptDate, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId, p.IsKeepNegativeAmount
			-- EndRegion #Result
		END
		ELSE
		BEGIN
			;WITH cte_WinLossData AS
			(
				SELECT ci.PartyId,
					b.RptDate3rd,
					b.CurrencyId,
					b.SiteId,
					SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.Turnover END) AS Turnover,
					SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.BetCount END) AS TotalTrans,
					SUM(CASE WHEN pb.bettype IS NOT NULL THEN b.Winloss ELSE 0 END) AS WinPrizeAmount,
					SUM(CASE WHEN b.BetTypeId = @JackpotPrize THEN b.Winloss ELSE 0 END) AS JackpotPrize,
					SUM(CASE WHEN b.BetTypeId = @Contribution THEN -b.AWinloss ELSE 0 END) AS LicenseeContribution,
					SUM(CASE WHEN b.BetTypeId = @Contribution THEN ProgressiveContribution ELSE 0 END) AS FullContribution,
					SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.Winloss END) AS CustomerWinLoss,
					SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE -b.Winloss END) AS LicenseeWinloss
				FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
					INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
					INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
					LEFT JOIN @PrizeBettype pb ON b.BetTypeId = pb.bettype
				WHERE b.RptDate BETWEEN @f_date AND @t_date
					AND b.RptDate3rd BETWEEN @f_date3rd AND @t_date3rd 
					AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
					AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
					AND ci.isDeposit = 1
				GROUP BY b.RptDate3rd, ci.PartyId, b.CurrencyId, b.SiteId
			)
			INSERT INTO #Result_PP (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,WinPrizeAmount,JackpotPrize,LicenseeContribution,FullContribution,CustomerWinLoss,LicenseeWinloss,LicensingFee,LicenseeChargeRate,PayToSupplier, IsKeepNegativeAmount)
			SELECT ci.PartyId,
				p.PartyName,
				p.ParentId,
				p.ParentName,
				b.RptDate3rd,
				b.CurrencyId,
				SUM(Turnover),
				SUM(TotalTrans),
				SUM(WinPrizeAmount),
				SUM(JackpotPrize),
				SUM(LicenseeContribution),
				SUM(FullContribution),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinloss),
				SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate) + LicenseeContribution - JackpotPrize - WinPrizeAmount) AS LicensingFee,
				SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
				SUM((LicenseeWinloss - FullContribution) * ci.Rate3rd) AS PayToSupplier,
				p.IsKeepNegativeAmount
			FROM cte_WinLossData b
				INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
				INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeId AND cr.CurrencyID = b.CurrencyId
			GROUP BY b.RptDate3rd, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId, p.IsKeepNegativeAmount
			-- EndRegion #Result
		END
		-- Region: Charge Info	
		DECLARE @CreditChargeInfos AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			isDeposit	BIT,
			ProductID	INT,
			Rate		MONEY,
			Rate3rd		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)	
	
		-- get licenseeFee's charge rate
		INSERT INTO @CreditChargeInfos(PartyId, ProductID, LicenseeId, isDeposit, Rate, Fromdate, Todate)
		(
			SELECT DISTINCT c.PartyID, c.ProductID, c.LicenseeID, ISNULL(c.isDeposit, 0) AS isDeposit,
				CASE WHEN ISNULL(c.isDeposit, 0) = 1 THEN c.Rate ELSE 0 END,
				c.Fromdate, c.Todate
			FROM @ChargeInfos c
			WHERE c.isDeposit <> 1		
		)
		-- End region
		IF @TimeZoneId = 1 
		BEGIN
			;WITH cte_WinLossData AS
			(
				SELECT ci.PartyId,
				b.RptDate,
				b.CurrencyId,
				b.SiteId,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.Turnover END)	AS Turnover,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.BetCount END)	AS TotalTrans,
				SUM(CASE WHEN pb.bettype IS NOT NULL THEN b.Winloss ELSE 0 END)									AS WinPrizeAmount,
				SUM(CASE WHEN b.BetTypeId = @JackpotPrize THEN b.Winloss ELSE 0 END)													AS JackpotPrize,
				SUM(CASE WHEN b.BetTypeId = @Contribution THEN -b.AWinloss ELSE 0 END)													AS LicenseeContribution,
				SUM(CASE WHEN b.BetTypeId = @Contribution THEN ProgressiveContribution ELSE 0 END)										AS FullContribution,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.Winloss END)		AS CustomerWinLoss,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE -b.Winloss END)	AS LicenseeWinloss
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
				INNER JOIN @CreditChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
				INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
				LEFT JOIN @PrizeBettype pb ON b.BetTypeId = pb.bettype
			WHERE b.RptDate BETWEEN @f_date3rd AND @t_date3rd
				AND b.RptDate3rd BETWEEN @f_date AND @t_date 
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
				AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
				AND ci.isDeposit = 0
			GROUP BY b.RptDate, ci.PartyId, b.CurrencyId, b.SiteId
			)
			INSERT INTO #Result_PP (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,WinPrizeAmount,JackpotPrize,LicenseeContribution,FullContribution,CustomerWinLoss,LicenseeWinloss,LicensingFee,LicenseeChargeRate, IsKeepNegativeAmount)
			SELECT ci.PartyId,
				p.PartyName,
				p.ParentId,
				p.ParentName,
				b.RptDate,
				b.CurrencyId,
				SUM(Turnover),
				SUM(TotalTrans),
				SUM(WinPrizeAmount),
				SUM(JackpotPrize),
				SUM(LicenseeContribution),
				SUM(FullContribution),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinloss),
				0,0,
				p.IsKeepNegativeAmount
			FROM cte_WinLossData b
				INNER JOIN @CreditChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate BETWEEN ci.FromDate AND ci.ToDate
				INNER JOIN @PartyList p ON ci.PartyId = p.PartyId
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.LicenseeId AND cr.CurrencyID = b.CurrencyId
			GROUP BY b.RptDate, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId, p.IsKeepNegativeAmount	 
			-- EndRegion #Result
		END
		ELSE
		BEGIN
			;WITH cte_WinLossData AS
			(
				SELECT ci.PartyId,
				b.RptDate3rd,
				b.CurrencyId,
				b.SiteId,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.Turnover END)	AS Turnover,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.BetCount END)	AS TotalTrans,
				SUM(CASE WHEN pb.bettype IS NOT NULL THEN b.Winloss ELSE 0 END)									AS WinPrizeAmount,
				SUM(CASE WHEN b.BetTypeId = @JackpotPrize THEN b.Winloss ELSE 0 END)													AS JackpotPrize,
				SUM(CASE WHEN b.BetTypeId = @Contribution THEN -b.AWinloss ELSE 0 END)													AS LicenseeContribution,
				SUM(CASE WHEN b.BetTypeId = @Contribution THEN ProgressiveContribution ELSE 0 END)										AS FullContribution,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE b.Winloss END)		AS CustomerWinLoss,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) OR pb.bettype IS NOT NULL THEN 0 ELSE -b.Winloss END)	AS LicenseeWinloss
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
				INNER JOIN @CreditChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
				INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
				LEFT JOIN @PrizeBettype pb ON b.BetTypeId = pb.bettype
			WHERE b.RptDate BETWEEN @f_date AND @t_date
				AND b.RptDate3rd BETWEEN @f_date3rd AND @t_date3rd 
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
				AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
				AND ci.isDeposit = 0
			GROUP BY b.RptDate3rd, ci.PartyId, b.CurrencyId, b.SiteId
			)

			INSERT INTO #Result_PP (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,WinPrizeAmount,JackpotPrize,LicenseeContribution,FullContribution,CustomerWinLoss,LicenseeWinloss,LicensingFee,LicenseeChargeRate, IsKeepNegativeAmount)
			SELECT ci.PartyId,
				p.PartyName,
				p.ParentId,
				p.ParentName,
				b.RptDate3rd,
				b.CurrencyId,
				SUM(Turnover),
				SUM(TotalTrans),
				SUM(WinPrizeAmount),
				SUM(JackpotPrize),
				SUM(LicenseeContribution),
				SUM(FullContribution),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinloss),
				0,0,
				p.IsKeepNegativeAmount
			FROM cte_WinLossData b
				INNER JOIN @CreditChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
				INNER JOIN @PartyList p ON ci.PartyId = p.PartyId
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.LicenseeId AND cr.CurrencyID = b.CurrencyId
			GROUP BY b.RptDate3rd, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId,p.IsKeepNegativeAmount	 
			-- EndRegion #Result
		END

		-- Region: Calculate Grand Total
		DECLARE @tempCurrency VARCHAR(20)
		DECLARE @NumberOfTiers INT = 2

		-- Region Credit
		DECLARE @RateOfCredit AS TABLE (
			RowIndex TINYINT IDENTITY(1,1),
			PartyId			INT,
			Rate			MONEY,
			MinAmount		MONEY,
			MaxAmount		MONEY,
			BaseCurrencyId	SMALLINT
		)
		INSERT INTO @RateOfCredit(PartyId, Rate, MinAmount, MaxAmount, BaseCurrencyId)
		SELECT DISTINCT	ci.FromParty, ci.Rate, MinAmount, MaxAmount, BaseCurrencyId
		FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
		INNER JOIN @CreditChargeInfos ci2 ON ci.FromParty = ci2.PartyId 
		WHERE ci2.isDeposit = 0 AND ci.ProductID = @ProductID
		ORDER BY FromParty, MaxAmount DESC

		-- Region TotalAmountOfCreditGroup
		DECLARE @CreditBaseCurrencyName VARCHAR(10), @CreditBaseCurrencyId INT
		SELECT TOP 1 @CreditBaseCurrencyName = [Name], @CreditBaseCurrencyId = BaseCurrencyId FROM @BaseCurrencies b INNER JOIN @RateOfCredit c ON c.BaseCurrencyId=b.Id

			-- Region: @TotalAmount_BasedOn_CreditBaseCurrencyName
		DECLARE @TotalAmount_BasedOn_CreditBaseCurrencyName MONEY, @TotalAmountWinLossBase MONEY
		SELECT @TotalAmount_BasedOn_CreditBaseCurrencyName = SUM((-r.CustomerWinLoss - r.FullContribution) * e.BaseCurrencyRate)
		FROM #Result_PP r
		INNER JOIN (SELECT DISTINCT PartyId FROM @RateOfCredit) roc ON r.PartyID = roc.PartyId
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CreditBaseCurrencyName) e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.Winlossdate
			-- End region: @TotalAmount_BasedOn_CreditBaseCurrencyName
		--Endregion TotalAmountOfCreditGroup

		-- Region Update PayToSupplier for #Result
		;WITH SumByPropressiveAmount AS(
			SELECT  r.PartyId,CurrencyId,Winlossdate,
					SUM(CASE 
						WHEN ((r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate) > MaxAmount THEN MaxAmount 
						WHEN ((r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate  - MinAmount) > 0 THEN ((r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate - MinAmount)
						WHEN (r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate < 0 AND roc.RowIndex % @NumberOfTiers = 0 THEN (r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate 
						ELSE 0 END  * roc.Rate / e.BaseCurrencyRate)  AS ProgressiveAmount
			FROM #Result_PP r 
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CreditBaseCurrencyName) e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.Winlossdate
			INNER JOIN @RateOfCredit roc ON r.PartyID = roc.PartyID
			GROUP BY r.PartyId,CurrencyId,Winlossdate
		)
		UPDATE r
		SET r.PayToSupplier = ProgressiveAmount
		FROM #Result_PP r
		INNER JOIN SumByPropressiveAmount s ON r.PartyId = s.PartyID AND r.CurrencyId = s.CurrencyId AND r.Winlossdate = s.Winlossdate
		-- Endregion Update PayToSupplier for #Result

		--Endregion Credit
		WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
		BEGIN
			SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		
			;WITH TotalByParty AS(
				SELECT CASE WHEN td.PartyID = 14 THEN PartyID ELSE td.ParentId END ParentId,
					SUM(td.TotalTrans)								TotalTrans,
					SUM(td.Turnover * e.BaseCurrencyRate)			Turnover, 
					SUM(td.WinPrizeAmount * e.BaseCurrencyRate)		WinPrizeAmount,
					SUM(ISNULL(td.JackpotPrize, 0) * e.BaseCurrencyRate)			JackpotPrize,
					SUM(ISNULL(td.LicenseeContribution, 0) * e.BaseCurrencyRate)	LicenseeContribution,
					SUM(ISNULL(td.FullContribution, 0) * e.BaseCurrencyRate)		FullContribution,
					SUM(td.CustomerWinLoss * e.BaseCurrencyRate)	CustomerWinLoss, 
					SUM(td.LicenseeWinLoss * e.BaseCurrencyRate)	LicenseeWinLoss, 
					SUM(td.LicensingFee * e.BaseCurrencyRate)		LicensingFee,
					SUM(ISNULL(td.LicenseeChargeRate, 0) * e.BaseCurrencyRate) LicenseeChargeRate,
					SUM(td.PayToSupplier * e.BaseCurrencyRate)		PayToSupplier,
					td.IsKeepNegativeAmount
				FROM #Result_PP td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e 
				ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
				GROUP BY CASE WHEN td.PartyID = 14 THEN PartyID ELSE td.ParentId END, td.PartyId, td.IsKeepNegativeAmount
			)
			INSERT INTO @Total_PP (Currency,PartyId,TotalTrans,Turnover,WinPrizeAmount,JackpotPrize,LicenseeContribution,FullContribution,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier)
			SELECT @tempCurrency,ParentId,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(WinPrizeAmount),
				SUM(JackpotPrize),
				SUM(LicenseeContribution),
				SUM(FullContribution),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(CASE WHEN ParentId = 999 THEN 0 -- Credit Licensee: always is 0
						 ELSE CASE WHEN LicenseeChargeRate < 0 AND IsKeepNegativeAmount = 0  THEN 0 ELSE LicenseeChargeRate END + LicenseeContribution - JackpotPrize - WinPrizeAmount
					END),
				SUM(PayToSupplier)
			FROM TotalByParty
			GROUP BY ParentId

			-- Region update PayToSupplier of Creadit
				;WITH SumByPropressiveAmount AS(
					SELECT  r.PartyId,
							SUM(CASE 
								WHEN @TotalAmount_BasedOn_CreditBaseCurrencyName > MaxAmount THEN MaxAmount * e.BaseCurrencyRate 
								WHEN @TotalAmount_BasedOn_CreditBaseCurrencyName  - MinAmount > 0 THEN (r.LicenseeWinloss - r.FullContribution) - (MinAmount * e.BaseCurrencyRate)
								WHEN @TotalAmount_BasedOn_CreditBaseCurrencyName < 0 AND roc.RowIndex % @NumberOfTiers = 0 THEN r.LicenseeWinloss - r.FullContribution
								ELSE 0 END  * roc.Rate)  AS ProgressiveAmount
					FROM @Total_PP r 
					INNER JOIN @RateOfCredit roc ON RowIndex <= @NumberOfTiers
					INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@ToDate, @ToDate, @tempCurrency) e ON @CreditBaseCurrencyId = e.ExchangeID
					WHERE r.Currency = @tempCurrency AND r.PartyId = 999 -- Credit Group Id
					GROUP BY r.PartyId 
				)
				UPDATE t
				SET PayToSupplier = ProgressiveAmount
				FROM @Total_PP t
				INNER JOIN SumByPropressiveAmount s ON t.PartyId = s.PartyID
				WHERE t.Currency = @tempCurrency
			-- Endregion update PayToSupplier of Creadit

			UPDATE @Total_PP
			SET PayToSupplier = CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END - WinPrizeAmount
			WHERE @tempCurrency = Currency

			INSERT INTO @GrandTotal_PP (CurrencyName,TotalTrans,Turnover,WinPrizeAmount,JackpotPrize,LicenseeContribution,FullContribution,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
			SELECT Currency,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(WinPrizeAmount),
				SUM(JackpotPrize),
				SUM(LicenseeContribution),
				SUM(FullContribution),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(LicensingFee),
				SUM(PayToSupplier),
				SUM(LicensingFee - PayToSupplier)
			FROM @Total_PP
			WHERE Currency = @tempCurrency
			GROUP BY Currency

			UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
		END	
		-- End Region

		-- Region: Select Result
		-- Currency report
			SELECT r.PartyId,
				r.PartyName,
				CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId,
				CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END ParentName,
				r.WinLossDate,
				r.CurrencyId,			 
				e.CurrencyCode AS CurrencyName,
				r.TotalTrans,
				-- base
				CAST(r.Turnover * e.Rate AS MONEY)			AS Turnover,
				CAST(r.WinPrizeAmount * e.Rate AS MONEY)	AS WinPrizeAmount,
				CAST(r.JackpotPrize * e.Rate AS MONEY)		AS JackpotPrize,
				CAST(r.LicenseeContribution * e.Rate AS MONEY)	AS LicenseeContribution,
				CAST(r.FullContribution * e.Rate AS MONEY)		AS FullContribution,
				CAST(r.CustomerWinLoss * e.Rate AS MONEY)	AS CustomerWinLoss,
				CAST(LicenseeWinLoss * e.Rate AS MONEY)		AS LicenseeWinLoss,
				CAST(r.LicensingFee * e.Rate AS MONEY)		AS LicensingFee,
				CAST(r.LicenseeChargeRate * e.Rate AS MONEY)	AS LicenseeChargeRate,
				CAST((PayToSupplier - WinPrizeAmount) * e.Rate AS MONEY)		AS PayToSupplier,
				CAST((r.LicensingFee - (PayToSupplier - WinPrizeAmount)) * e.Rate AS MONEY) AS CompanyIncome,
				-- original
				r.Turnover			AS TurnoverOriginal,
				r.WinPrizeAmount	AS WinPrizeAmountOriginal,
				r.JackpotPrize		AS JackpotPrizeOriginal,
				r.LicenseeContribution	AS LicenseeContributionOriginal,
				r.FullContribution		AS FullContributionOriginal,
				r.CustomerWinLoss	AS CustomerWinLossOriginal,
				r.LicenseeWinLoss	AS LicenseeWinLossOriginal,
				r.LicensingFee		AS LicensingFeeOriginal,
				r.LicenseeChargeRate	AS LicenseeChargeRateOriginal,
				PayToSupplier - WinPrizeAmount		AS PayToSupplierOriginal,
				(r.LicensingFee - (PayToSupplier - WinPrizeAmount)) AS CompanyIncomeOriginal
			FROM #Result_PP r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate
	
		

		-- Total By Party
		;WITH cte_TotalAmountByParty_BasedOn_CreditCurrency AS
		(
			SELECT r.PartyId, SUM((r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate) AS TotalAmount_BasedOn_CreditCurrency
			FROM #Result_PP r
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CreditBaseCurrencyName) e ON r.CurrencyId = e.ExchangeID AND r.Winlossdate = e.exchangedate
			GROUP BY r.PartyId
		), cte_TempData AS
		(
			SELECT r.PartyId, r.PartyName, r.ParentId,
			SUM(r.TotalTrans) TotalTrans,
			SUM(CAST(r.Turnover * e.Rate AS MONEY))			AS Turnover,
			SUM(CAST(r.WinPrizeAmount * e.Rate AS MONEY))	AS WinPrizeAmount,
			SUM(CAST(r.JackpotPrize * e.Rate AS MONEY))		AS JackpotPrize,
			SUM(CAST(r.LicenseeContribution * e.Rate AS MONEY))		AS LicenseeContribution,
			SUM(CAST(r.FullContribution * e.Rate AS MONEY))			AS FullContribution,
			SUM(CAST(r.CustomerWinLoss * e.Rate AS MONEY))	AS CustomerWinLoss,
			SUM(CAST(LicenseeWinLoss * e.Rate AS MONEY))	AS LicenseeWinLoss,
			SUM(CAST(r.LicenseeChargeRate * e.Rate AS MONEY)) AS LicenseeChargeRate,
			SUM(CAST((r.PayToSupplier - WinPrizeAmount) * e.Rate AS MONEY)) AS PayToSupplier,
			r.IsKeepNegativeAmount
			FROM #Result_PP r 
			INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate
			GROUP BY r.PartyId, r.PartyName, r.ParentId, r.IsKeepNegativeAmount
		), cte_TempResult AS
		(
			SELECT PartyId,PartyName,CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId,TotalTrans,Turnover,WinPrizeAmount,JackpotPrize,LicenseeContribution,FullContribution,CustomerWinLoss,LicenseeWinLoss
				,CASE WHEN PartyID IN(25,30) THEN 0 
						ELSE CASE WHEN LicenseeChargeRate < 0 AND IsKeepNegativeAmount = 0 THEN 0 ELSE  LicenseeChargeRate END + LicenseeContribution - JackpotPrize - WinPrizeAmount 
					END AS LicensingFee
				, CASE WHEN PartyID IN(25,30)
						THEN (SELECT TOP 1 SUM(CASE
							WHEN r3.TotalAmount_BasedOn_CreditCurrency > MaxAmount THEN MaxAmount * e.BaseCurrencyRate 
							WHEN r3.TotalAmount_BasedOn_CreditCurrency - MinAmount > 0 THEN (r2.LicenseeWinLoss - r2.FullContribution) - (MinAmount * e.BaseCurrencyRate)
							WHEN r3.TotalAmount_BasedOn_CreditCurrency < 0 AND roc.RowIndex % @NumberOfTiers = 0 THEN r2.LicenseeWinLoss - r2.FullContribution
							ELSE 0 END  * roc.Rate)
							FROM @RateOfCredit roc
								INNER JOIN cte_TempData r2 ON r2.PartyID = roc.PartyId
								INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@ToDate, @ToDate, @BaseCurrencyName) e ON @CreditBaseCurrencyId = e.ExchangeID 
								INNER JOIN cte_TotalAmountByParty_BasedOn_CreditCurrency r3 ON r3.PartyID = r2.PartyID
							WHERE r1.PartyID = r2.PartyID) - WinPrizeAmount
						ELSE  PayToSupplier
					END AS PayToSupplier
			FROM cte_TempData r1
		)
		SELECT *, LicensingFee - PayToSupplier AS CompanyIncome
		FROM cte_TempResult

		-- Grand Total
		SELECT * FROM @GrandTotal_PP

		-- Total By Party Group
		SELECT PartyId,TotalTrans,Turnover,WinPrizeAmount,JackpotPrize,LicenseeContribution,FullContribution,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,
				LicensingFee - PayToSupplier AS CompanyIncome
		FROM @Total_PP t
		WHERE Currency = @BaseCurrencyName

		-- End Region
		DROP TABLE #Result_PP
	END
	DROP TABLE #Exchange

END
GO