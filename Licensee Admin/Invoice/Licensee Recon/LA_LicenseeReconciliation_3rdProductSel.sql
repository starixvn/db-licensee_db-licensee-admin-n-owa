/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_3rdProductSel]
	@PartyIds			VARCHAR(MAX)
	,@ProductId			INT = 31
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(10) = 'EUR'
AS

/*
	Created: 20210727@Percy
	DB: DBLIC-bodb_Licensee
	Task: Get data from NAP - Separate products

	Revisions: 
		- 20210727@Percy: Initialize SP [RedmineID: #155593]
		- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME
	DECLARE @BalanceUpDay SMALLDATETIME, @MoveBetsDay SMALLDATETIME

	DECLARE @MBBU TABLE (BalanceUpDay SMALLDATETIME, MoveBetsDay SMALLDATETIME)
	INSERT INTO @MBBU (BalanceUpDay, MoveBetsDay)
	EXEC bodb02.dbo.Age_SelBalanceUpDay

	SELECT @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay FROM @MBBU

	DECLARE @ProductCode VARCHAR(10), @Bettype SMALLINT
	
	IF @ProductId = 31 -- Exchange
		SELECT @ProductCode = 'BX', @Bettype = 8000
	ELSE IF @ProductId = 10 -- AG Casino
		SELECT @ProductCode = 'AGC', @Bettype = 1800

	DECLARE @tblSite TABLE (SiteId INT, Site VARCHAR(100))
	INSERT INTO @tblSite (SiteId, Site)
	SELECT l.LicenseeId, l.LicenseeName
	FROM bodb_Licensee.dbo.Licensees l WITH (NOLOCK)
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON l.LicenseeId = p.OldRefId AND p.PartyType IN (1, 5)
	WHERE p.PartyId IN (SELECT CONVERT(INT, val) FROM bodb02.dbo.strSplit(@PartyIds, ','))

	-- Get Exchange
	DECLARE @Exchange TABLE (ExchangeId INT, ExchangeDate SMALLDATETIME, Code VARCHAR(65), Rate FLOAT)
	INSERT INTO @Exchange (ExchangeId, ExchangeDate, Code, Rate)
	SELECT ExchangeId, ExchangeDate, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @BaseCurrencyName)

	-- I. LA
	BEGIN
		DECLARE @ChargeRate TABLE (ChargeId INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME, Rate FLOAT)
		INSERT INTO @ChargeRate (ChargeId, FromDate, ToDate, Rate)
		SELECT ChargeId, FromDate, ToDate, DI_Rate
		FROM dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, @ProductCode, 'OA', 1)

		DECLARE @ChargeRateByCurrency TABLE (ChargeId INT, Currency INT, Rate FLOAT)
		INSERT INTO @ChargeRateByCurrency (ChargeId, Currency, Rate)
		SELECT bc.ChargeId, bc.CurrencyId, bc.Rate
		FROM dbo.LA_ChargeRateByCurrency bc WITH (NOLOCK)
			INNER JOIN @ChargeRate c ON bc.ChargeId = c.ChargeId

		CREATE TABLE #tmpLAData (winlostdate SMALLDATETIME, Currency INT, MemberWL MONEY, Comm MONEY)
		INSERT INTO #tmpLAData (winlostdate, Currency, MemberWL, Comm)
		SELECT r.rptDate, r.CurrencyId
			,SUM(r.MemberWL) AS MemberWL
			,SUM(r.CommissionA + r.CommissionP) AS Comm
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
			INNER JOIN @tblSite s ON r.SiteId = s.SiteId
		WHERE r.rptDate BETWEEN @FromDate AND @ToDate
			AND r.ProductId = @ProductId
			AND r.StatusId NOT IN (-1, 101, 102, 103)
			AND r.CustomerCategory NOT IN (27, 28)
			AND r.CurrencyId <> 20
		GROUP BY r.rptDate, r.CurrencyId
	END

	-- II. NAP
	BEGIN
		-- Get dummy account
		DECLARE @tblCustId TABLE (CustId INT)
		INSERT INTO @tblCustId (CustId)
		SELECT c.CustId
		FROM @tblSite s
			INNER JOIN bodb02.dbo.Customer m WITH (NOLOCK) ON s.Site = m.Site AND m.roleid = 3
			INNER JOIN bodb02.dbo.customer c WITH (NOLOCK) ON m.custid = c.mrecommend AND c.roleid = 1
		WHERE m.username LIKE '%Acc%'
			AND c.username LIKE '%Dummy3rd%'
			AND m.currency <> 20

		-- Get data
		CREATE TABLE #tmpNAPData (winlostdate SMALLDATETIME, actual_winlostdate SMALLDATETIME, currency INT, transdesc NVARCHAR(1000), AmountToCompany MONEY)
		IF @ToDate > @MoveBetsDay
		BEGIN
			SELECT @FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
				,@TDate = @ToDate
		
			INSERT INTO #tmpNAPData (winlostdate, currency, transdesc, AmountToCompany)
			SELECT b.winlostdate, b.currency, b.transdesc, SUM(swinlost + mwinlost + awinlost + winlost - actual_stake + scomm)
			FROM bodb02.dbo.bettrans b WITH (NOLOCK)
				INNER JOIN @tblCustId c ON b.custid = c.CustId
			WHERE b.winlostdate BETWEEN @FDate AND @TDate
				AND b.currency <> 20
				AND b.statusId IN (111, 112, 113)
				AND b.bettype = @Bettype
			GROUP BY b.winlostdate, b.currency, b.transdesc
		END

		IF @FromDate <= @MoveBetsDay AND @ToDate >= @BalanceUpDay
		BEGIN
			SELECT @FDate = CASE WHEN @FromDate < @BalanceUpDay THEN @BalanceUpDay ELSE @FromDate END
				,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			INSERT INTO #tmpNAPData (winlostdate, currency, transdesc, AmountToCompany)
			SELECT b.winlostdate, b.currency, b.transdesc, SUM(swinlost + mwinlost + awinlost + winlost - actual_stake + scomm)
			FROM bodb02.dbo.bettrans14 b WITH (NOLOCK)
				INNER JOIN @tblCustId c ON b.custid = c.CustId
			WHERE b.winlostdate BETWEEN @FDate AND @TDate
				AND b.currency <> 20
				AND b.statusId IN (111, 112, 113)
				AND b.bettype = @Bettype
			GROUP BY b.winlostdate, b.currency, b.transdesc
		END

		IF @FromDate < @BalanceUpDay
		BEGIN
			SELECT @FDate = @FromDate
				,@TDate = CASE WHEN @ToDate >= @BalanceUpDay THEN DATEADD(DAY, -1, @BalanceUpDay) ELSE @ToDate END

			DECLARE @CustIds VARCHAR(MAX), @SQL VARCHAR(MAX)

			SELECT @CustIds = COALESCE(@CustIds + ',', '') + CONVERT(VARCHAR(20), CustId) FROM @tblCustId
			SET @SQL = 'SELECT winlostdate, currency, transdesc, AmountToCompany
						FROM OPENQUERY(DBARC, ''SELECT winlostdate, currency, transdesc, SUM(swinlost + mwinlost + awinlost + winlost - actual_stake + scomm) AS AmountToCompany
												FROM bodb_Archive.dbo.bettrans_bk WITH (NOLOCK)
												WHERE winlostdate BETWEEN ''''' + CONVERT(VARCHAR(10), @FDate, 120) + ''''' AND ''''' + CONVERT(VARCHAR(10), @TDate, 120) + '''''
													AND custid IN (' + @CustIds + ')
													AND currency <> 20
													AND statusId IN (111, 112, 113)
													AND bettype = ' + CONVERT(VARCHAR(20), @Bettype) + '
												GROUP BY winlostdate, currency, transdesc'')'

			INSERT INTO #tmpNAPData (winlostdate, currency, transdesc, AmountToCompany)
			EXEC (@SQL)
		END

		-- update winlostdate of adjustment ticket
		UPDATE #tmpNAPData
		SET actual_winlostdate = CASE WHEN transdesc LIKE '%Adjustment - Date:%' THEN SUBSTRING(transdesc, CHARINDEX('Date: ', transdesc, 0) + 6, 10) ELSE winlostdate END
	END

	-- Result
	BEGIN
		DECLARE @Result TABLE (Func VARCHAR(10), Currency VARCHAR(10), [Type] VARCHAR(200), AmountToCompany MONEY, ExRate FLOAT, BasedAmountToCompany MONEY)
		
		-- LA
		INSERT INTO @Result (Func, Currency, [Type], ExRate, AmountToCompany, BasedAmountToCompany)
		SELECT 'LA', e.Code, 'Actual Bet', e.Rate
			,SUM(d.MemberWL * ISNULL(bc.Rate, c.Rate) + d.Comm) AS AmountToCompany
			,SUM((d.MemberWL * ISNULL(bc.Rate, c.Rate) + d.Comm) * e.Rate) AS BasedAmountToCompany
		FROM #tmpLAData d
			INNER JOIN @Exchange e ON d.Currency = e.ExchangeId AND d.winlostdate = e.ExchangeDate
			INNER JOIN @ChargeRate c ON d.winlostdate BETWEEN c.FromDate AND c.ToDate
			LEFT JOIN @ChargeRateByCurrency bc ON c.ChargeId = bc.ChargeId AND d.Currency = bc.Currency
		GROUP BY e.Code, e.Rate

		-- NAP
		INSERT INTO @Result (Func, Currency, [Type], ExRate, AmountToCompany, BasedAmountToCompany)
		SELECT 'NAP', e.Code
			,CASE WHEN actual_winlostdate BETWEEN @FromDate AND @ToDate THEN 'Actual Bet' ELSE 'Adjustment without this month' END AS [Type]
			,e.Rate AS ExRate
			,SUM(d.AmountToCompany) AS AmountToCompany
			,SUM(d.AmountToCompany * e.Rate) AS BasedAmountToCompany
		FROM #tmpNAPData d
			INNER JOIN @Exchange e ON d.Currency = e.ExchangeId AND d.winlostdate = e.ExchangeDate
		GROUP BY
			e.Code
			,CASE WHEN actual_winlostdate BETWEEN @FromDate AND @ToDate THEN 'Actual Bet' ELSE 'Adjustment without this month' END
			,e.Rate
	END

	-- Return data
		-- LA
	SELECT Currency, [Type], ExRate, AmountToCompany AS ServiceFee, BasedAmountToCompany AS BasedServiceFee
	FROM @Result
	WHERE Func = 'LA'
	ORDER BY Currency, [Type]

		-- NAP
	SELECT Currency, [Type], ExRate, AmountToCompany AS ServiceFee, BasedAmountToCompany AS BasedServiceFee
	FROM @Result
	WHERE Func = 'NAP'
	ORDER BY Currency, [Type]

		-- Variance
	DECLARE @Diff_BasedServiceFee MONEY
	SELECT  @Diff_BasedServiceFee = SUM(BasedAmountToCompany * CASE WHEN Func = 'LA' THEN 1.0 ELSE -1.0 END)
	FROM @Result

	SELECT ISNULL(@Diff_BasedServiceFee, 0) AS BasedServiceFee
	
	DROP TABLE #tmpLAData
	DROP TABLE #tmpNAPData
END
GO