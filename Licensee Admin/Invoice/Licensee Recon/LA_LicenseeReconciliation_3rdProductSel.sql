/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_3rdProductSel]
	@PartyId			INT
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
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME, @SQL VARCHAR(MAX)
	DECLARE @BalanceUpDay SMALLDATETIME, @MoveBetsDay SMALLDATETIME

	DECLARE @MBBU TABLE (BalanceUpDay SMALLDATETIME, MoveBetsDay SMALLDATETIME)
	INSERT INTO @MBBU (BalanceUpDay, MoveBetsDay)
	EXEC dbo.Age_SelBalanceUpDay

	SELECT @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay FROM @MBBU

	DECLARE @ProductCode VARCHAR(10), @Bettype SMALLINT, @SiteId INT, @SiteName VARCHAR(50)
	
	IF @ProductId = 31 -- Exchange
		SELECT @ProductCode = 'BX', @Bettype = 8000
	ELSE IF @ProductId = 10 -- AG Casino
		SELECT @ProductCode = 'AGC', @Bettype = 1800

	SELECT @SiteId = l.LicenseeId, @SiteName = l.LicenseeName
	FROM bodb_Licensee.dbo.Licensees l WITH (NOLOCK)
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON l.LicenseeId = p.OldRefId AND p.PartyType IN (1, 5)
	WHERE p.PartyId = @PartyId

	-- Get Exchange
	DECLARE @Exchange TABLE (ExchangeId INT, ExchangeDate SMALLDATETIME, Code VARCHAR(10), Rate FLOAT)

	SET @SQL = 'SELECT ExchangeId, ExchangeDate, Code, BaseCurrencyRate
				FROM OPENQUERY(DBAGE, ''SELECT ExchangeId, ExchangeDate, Code, BaseCurrencyRate
										FROM bodb02.dbo.LA_f_ExchangeDailySel(''''' + CONVERT(VARCHAR(10), @FromDate, 120) + + ''''', ''''' + + CONVERT(VARCHAR(10), @ToDate, 120) + ''''', ''''' + @BaseCurrencyName + ''''')'')'
	INSERT INTO @Exchange (ExchangeId, ExchangeDate, Code, Rate)
	EXEC (@SQL)

	-- I. LA
	BEGIN
		DECLARE @ChargeRate TABLE (ChargeId INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME, Rate FLOAT)

		SET @SQL = 'SELECT ChargeId, FromDate, ToDate, DI_Rate
					FROM OPENQUERY(DBLIC, ''SELECT ChargeId, FromDate, ToDate, DI_Rate
											FROM bodb_Licensee.dbo.LA_f_ChargeInfo (''''' + CONVERT(VARCHAR(20), @PartyId) + ''''', ''''' + CONVERT(VARCHAR(10), @FromDate, 120) + ''''', ''''' + CONVERT(VARCHAR(10), @ToDate, 120) + ''''', ''''' + @ProductCode + ''''', ''''OA'''', 1) c
											WHERE DI_Rate > 0'')'
		INSERT INTO @ChargeRate (ChargeId, FromDate, ToDate, Rate)
		EXEC (@SQL)

		DECLARE @ChargeRateByCurrency TABLE (ChargeId INT, Currency INT, Rate FLOAT)

		SET @SQL = 'SELECT ChargeId, CurrencyId, Rate
					FROM OPENQUERY(DBLIC, ''SELECT bc.ChargeId, bc.CurrencyId, bc.Rate
											FROM bodb_Licensee.dbo.LA_f_ChargeInfo (''''' + CONVERT(VARCHAR(20), @PartyId) + ''''', ''''' + CONVERT(VARCHAR(10), @FromDate, 120) + ''''', ''''' + CONVERT(VARCHAR(10), @ToDate, 120) + ''''', ''''' + @ProductCode + ''''', ''''OA'''', 1) c
												INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency bc WITH (NOLOCK) ON c.ChargeId = bc.ChargeId
											WHERE c.DI_Rate > 0'')'
		INSERT INTO @ChargeRateByCurrency (ChargeId, Currency, Rate)
		EXEC (@SQL)

		CREATE TABLE #tmpLAData (winlostdate SMALLDATETIME, Currency INT, MemberWL MONEY, Comm MONEY)
		INSERT INTO #tmpLAData (winlostdate, Currency, MemberWL, Comm)
		SELECT rptDate, CurrencyId
			,SUM(MemberWL) AS MemberWL
			,SUM(CommissionA + CommissionP) AS Comm
		FROM DBLIC.bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
		WHERE rptDate BETWEEN @FromDate AND @ToDate
			AND SiteId = @SiteId
			AND ProductId = @ProductId
			AND StatusId NOT IN (-1, 101, 102, 103)
			AND CustomerCategory NOT IN (27, 28)
			AND CurrencyId <> 20
		GROUP BY rptDate, CurrencyId
	END

	-- II. NAP
	BEGIN
		-- Get dummy account
		DECLARE @CustIds TABLE (CustId INT)
		INSERT INTO @CustIds (CustId)
		SELECT c.CustId
		FROM dbo.customer c WITH (NOLOCK)
		WHERE c.mrecommend IN (
			SELECT m.custid
			FROM dbo.Customer m WITH (NOLOCK)
			WHERE m.username LIKE '%Acc%' AND m.roleid = 3 AND m.Site = @SiteName
		)
			AND c.username LIKE '%Dummy3rd%'
			AND c.roleid = 1

		-- Get data
		CREATE TABLE #tmpNAPData (winlostdate SMALLDATETIME, actual_winlostdate SMALLDATETIME, currency INT, transdesc NVARCHAR(1000), AmountToCompany MONEY)
		IF @ToDate > @MoveBetsDay
		BEGIN
			SELECT @FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
				,@TDate = @ToDate
		
			INSERT INTO #tmpNAPData (winlostdate, currency, transdesc, AmountToCompany)
			SELECT b.winlostdate, b.currency, b.transdesc, -SUM(swinlost + mwinlost + awinlost + winlost - actual_stake + scomm)
			FROM dbo.bettrans b WITH (NOLOCK)
				INNER JOIN @CustIds c ON b.custid = c.CustId
			WHERE b.winlostdate BETWEEN @FDate AND @TDate
				AND b.currency <> 20
				AND b.statusId IN (111, 112, 113)
				AND b.bettype = @Bettype
			GROUP BY b.winlostdate, b.currency, b.transdesc
		END

		IF @FromDate <= @MoveBetsDay
		BEGIN
			SELECT @FDate = CASE WHEN @FromDate < @BalanceUpDay THEN @BalanceUpDay ELSE @FromDate END
				,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			INSERT INTO #tmpNAPData (winlostdate, currency, transdesc, AmountToCompany)
			SELECT b.winlostdate, b.currency, b.transdesc, -SUM(swinlost + mwinlost + awinlost + winlost - actual_stake + scomm)
			FROM dbo.bettrans14 b WITH (NOLOCK)
				INNER JOIN @CustIds c ON b.custid = c.CustId
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

			INSERT INTO #tmpNAPData (winlostdate, currency, transdesc, AmountToCompany)
			SELECT b.winlostdate, b.currency, b.transdesc, -SUM(swinlost + mwinlost + awinlost + winlost - actual_stake + scomm)
			FROM bodb_Archive.dbo.bettrans_bk b WITH (NOLOCK)
				INNER JOIN @CustIds c ON b.custid = c.CustId
			WHERE b.winlostdate BETWEEN @FDate AND @TDate
				AND b.currency <> 20
				AND b.statusId IN (111, 112, 113)
				AND b.bettype = @Bettype
			GROUP BY b.winlostdate, b.currency, b.transdesc
		END

		-- update winlostdate of adjustment ticket
		UPDATE #tmpNAPData
		SET actual_winlostdate = CASE WHEN transdesc LIKE '%Adjustment - Date:%' THEN SUBSTRING(transdesc, CHARINDEX('Date: ', transdesc, 0) + 6, 10) ELSE winlostdate END
	END

	-- Return data
		-- LA
	SELECT
		e.Code AS Currency
		,'Actual Bet' AS [Type]
		,SUM(-d.MemberWL * ISNULL(bc.Rate, c.Rate) - d.Comm) AS AmountToCompany
		,e.Rate AS ExRate
		,SUM((-d.MemberWL * ISNULL(bc.Rate, c.Rate) - d.Comm) * e.Rate) AS BasedAmountToCompany
	FROM #tmpLAData d
		INNER JOIN @Exchange e ON d.Currency = e.ExchangeId AND d.winlostdate = e.ExchangeDate
		INNER JOIN @ChargeRate c ON d.winlostdate BETWEEN c.FromDate AND c.ToDate
		LEFT JOIN @ChargeRateByCurrency bc ON c.ChargeId = bc.ChargeId AND d.Currency = bc.Currency
	GROUP BY
		e.Code
		,e.Rate
	ORDER BY Currency

		-- NAP
	SELECT
		e.Code AS Currency
		,CASE WHEN actual_winlostdate BETWEEN @FromDate AND @ToDate THEN 'Actual Bet' ELSE 'Adjustment without this month' END AS [Type]
		,SUM(d.AmountToCompany) AS AmountToCompany
		,e.Rate AS ExRate
		,SUM(d.AmountToCompany * e.Rate) AS BasedAmountToCompany
	FROM #tmpNAPData d
		INNER JOIN @Exchange e ON d.Currency = e.ExchangeId AND d.winlostdate = e.ExchangeDate
	GROUP BY
		e.Code
		,CASE WHEN actual_winlostdate BETWEEN @FromDate AND @ToDate THEN 'Actual Bet' ELSE 'Adjustment without this month' END
		,e.Rate
	ORDER BY Currency, [Type]
	
	DROP TABLE #tmpLAData
	DROP TABLE #tmpNAPData
END
GO