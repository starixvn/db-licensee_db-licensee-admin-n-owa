USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Report_GetTotalTicket_xtest]    Script Date: 07/11/2014 10:28:19 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Report_GetTotalTicket] 
     @NormalLicensee 	VARCHAR(1000)
	,@Operator 		VARCHAR(1000)
	,@FromDate 		SMALLDATETIME
	,@ToDate 			SMALLDATETIME
	,@SportID 		INT 			= 0
	,@GroupBy 		TINYINT 		= 2
AS
/*  
 * Created by : 20131203@Francis 
 * Task  : Get Total Transactions report for Sportbook (compatible with the new structure)
 * DB   : DB052.bodb02
 * Revisions :  
 	- 20141103@Florent: use new structure (#25393)
	- 20150412@Patrick: Add filter by PartyType

 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','  
 *  - @GroupBy: + Value = 1: Daily grouping type
			    + Value = 2: Monthly grouping type
 */
BEGIN
	SELECT @Fromdate = ltrim(rtrim(@Fromdate))
		,@Todate = ltrim(rtrim(@Todate))

	--declare
	DECLARE @tmpLicenseeReseller AS TABLE (
		FromPartyID INT
		,ToPartyID INT
		,FromDate DATETIME
		,OldRefID INT
		)
	DECLARE @data AS TABLE (
		Winlostdate SMALLDATETIME
		,FromPartyID INT
		,ToPartyID INT
		,BetCount INT
		)
	DECLARE @tmpTotalBet AS TABLE (
		GroupBy VARCHAR(8)
		,ResellerID INT
		,ResellerName VARCHAR(50)
		,LicenseeName VARCHAR(50)
		,BetCount INT
		)
	DECLARE @tmpTable AS TABLE (PartyID INT)

	INSERT INTO @tmpTable (PartyID)
	SELECT PartyID
	FROM bodb_licensee.dbo.OAS_Party(NOLOCK)
	WHERE PartyName IN ('Starlit', 'BA(FDL)')
		AND PartyType NOT IN (4)

	--enhance performance
	CREATE TABLE #tmpBetting (
		rptDate DATETIME
		,siteID INT
		,betcount INT
		)

	CREATE TABLE #tmpBetting_BA (
		rptDate DATETIME
		,siteID INT
		,betcount INT
		)

	IF @SportID <> 0
	BEGIN
		INSERT INTO #tmpBetting (
			rptDate
			,siteID
			,betcount
			)
		SELECT b.rptDate
			,b.SiteID
			,SUM(b.betcount)
		FROM bodb_licensee.dbo.rpt_betting b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.leagueid = l.leagueid
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.STATUS NOT IN (- 1, 103)
			AND b.CurrencyID <> 20
			AND ISNULL(b.CustomerCategory, 0) NOT IN (27, 28)
			AND (
				b.bettype < 31
				OR b.bettype BETWEEN 121 AND 999
				OR b.bettype BETWEEN 1301 AND 1399
				)
			AND b.bettype NOT IN (9, 29)
			AND l.Sporttype = convert(VARCHAR(10), @SportID)
		GROUP BY b.rptDate
			,b.SiteID

		INSERT INTO #tmpBetting_BA (
			rptDate
			,siteID
			,betcount
			)
		SELECT b.rptDate
			,b.SiteID
			,SUM(b.betcount)
		FROM bodb_licensee.dbo.rpt_betting_BA b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.leagueid = l.leagueid
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.STATUS NOT IN (- 1, 103)
			AND b.CurrencyID <> 20
			AND b.bettype NOT IN (9, 29)
			AND l.Sporttype = convert(VARCHAR(10), @SportID)
		GROUP BY b.rptDate
			,b.SiteID
	END
	ELSE
	BEGIN
		INSERT INTO #tmpBetting (
			rptDate
			,siteID
			,betcount
			)
		SELECT b.rptDate
			,b.SiteID
			,SUM(b.betcount)
		FROM bodb_licensee.dbo.rpt_betting b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.leagueid = l.leagueid
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.STATUS NOT IN (- 1, 103)
			AND b.CurrencyID <> 20
			AND ISNULL(b.CustomerCategory, 0) NOT IN (27, 28)
			AND (
				b.bettype < 31
				OR b.bettype BETWEEN 121 AND 999
				OR b.bettype BETWEEN 1301 AND 1399
				)
		GROUP BY b.rptDate
			,b.SiteID

		INSERT INTO #tmpBetting_BA (
			rptDate
			,siteID
			,betcount
			)
		SELECT b.rptDate
			,b.SiteID
			,SUM(b.betcount)
		FROM bodb_licensee.dbo.rpt_betting_BA b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.leagueid = l.leagueid
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.STATUS NOT IN (- 1, 103)
			AND b.CurrencyID <> 20
		GROUP BY b.rptDate
			,b.SiteID
	END

	--end enhancement
	IF LTRIM(RTRIM(ISNULL(@NormalLicensee, ''))) <> ''
	BEGIN
		INSERT INTO @tmpLicenseeReseller (
			FromPartyID
			,ToPartyID
			,FromDate
			,OldRefID
			)
		SELECT DISTINCT ci.FromParty
			,ci.ToParty
			,CASE 
				WHEN @FromDate <= ci.FromDate
					THEN ci.FromDate
				ELSE @FromDate
				END
			,p.OldRefID
		FROM bodb_licensee.dbo.OAS_ChargeInfo ci(NOLOCK)
		INNER JOIN bodb_Licensee.dbo.OAS_Party p(NOLOCK) ON ci.FromParty = p.PartyID
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4
		WHERE (
				@FromDate BETWEEN ci.FromDate AND ci.ToDate
				OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
				)
			AND ci.ChargeType = 2
			AND ci.ProductID = 0
			--just get Licensees from Oneworks,BCH and LDL
			AND ci.ToParty IN (
				SELECT PartyID
				FROM bodb_Licensee.dbo.OAS_Party(NOLOCK)
				WHERE PartyName IN ('Oneworks', 'BCH', 'LDL') AND PartyType NOT IN (4)
				)
			--strSplit is a user-defined function
			AND ci.FromParty IN (
				SELECT RTRIM(LTRIM(VAL))
				FROM strSplit(@NormalLicensee, ',')
				)
	END

	IF LTRIM(RTRIM(ISNULL(@Operator, ''))) <> ''
	BEGIN
		INSERT INTO @tmpLicenseeReseller (
			FromPartyID
			,ToPartyID
			,FromDate
			,OldRefID
			)
		SELECT DISTINCT ci.FromParty
			,ci.ToParty
			,CASE 
				WHEN @FromDate <= ci.FromDate
					THEN ci.FromDate
				ELSE @FromDate
				END
			,p.OldRefID
		FROM bodb_licensee.dbo.OAS_ChargeInfo ci(NOLOCK)
		INNER JOIN bodb_Licensee.dbo.OAS_Party p(NOLOCK) ON ci.FromParty = p.PartyID
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4
		WHERE (
				@FromDate BETWEEN ci.FromDate AND ci.ToDate
				OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
				)
			AND ci.ChargeType = 2
			AND ci.ProductID = 0
			AND ci.ToParty IN (
				SELECT RTRIM(LTRIM(VAL))
				FROM strSplit(@Operator, ',')
				)
	END

	--1. Exclude Licensees from Starlit and BA(FDL)
	--For Deposit Licensees 
	IF EXISTS (
			SELECT 1
			FROM @tmpLicenseeReseller tlr
			WHERE tlr.ToPartyID NOT IN (
					SELECT PartyID
					FROM @tmpTable
					)
			)
	BEGIN
		IF EXISTS (
				SELECT 1
				FROM @tmpLicenseeReseller tlr
				INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1(NOLOCK) ON tlr.FromPartyID = pd1.PartyID
				WHERE pd1.IsDeposit = 1
				)
		BEGIN
			INSERT INTO @data (
				Winlostdate
				,FromPartyID
				,ToPartyID
				,BetCount
				)
			SELECT b.rptDate
				,lr.FromPartyID
				,lr.ToPartyID
				,SUM(betcount) AS BetCount
			FROM #tmpBetting b(NOLOCK)
			INNER JOIN @tmpLicenseeReseller lr ON b.siteID = lr.OldRefID
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd(NOLOCK) ON lr.FromPartyID = pd.PartyID
			WHERE pd.IsDeposit = 1
				AND b.rptDate BETWEEN lr.FromDate AND @ToDate
						--Exclude Licensees from Starlit, BA(FDL)
				AND lr.ToPartyID NOT IN (
					SELECT PartyID
					FROM @tmpTable
					)
			GROUP BY b.rptDate
				,lr.FromPartyID
				,lr.ToPartyID
		END

		--For Credit Licensees
		IF EXISTS (
				SELECT 1
				FROM @tmpLicenseeReseller tlr
				INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1(NOLOCK) ON tlr.FromPartyID = pd1.PartyID
				WHERE pd1.IsDeposit = 0
				)
		BEGIN
			INSERT INTO @data (
				Winlostdate
				,FromPartyID
				,ToPartyID
				,BetCount
				)
			SELECT b.rptDate
				,lr.FromPartyID
				,lr.ToPartyID
				,SUM(betcount) AS BetCount
			FROM @tmpLicenseeReseller lr
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd(NOLOCK) ON lr.FromPartyID = pd.PartyID
			INNER JOIN bodb_Licensee.dbo.labels lb(NOLOCK) ON lr.OldRefID = lb.LicenseeID
			INNER JOIN #tmpBetting b(NOLOCK) ON b.siteID = lb.LabelID
			WHERE pd.IsDeposit = 0
				AND b.rptDate BETWEEN lr.FromDate AND @ToDate
						--Exclude Licensees from Starlit, BA(FDL)
				AND lr.ToPartyID NOT IN (
					SELECT PartyID
					FROM @tmpTable
					)
			GROUP BY b.rptDate
				,lr.FromPartyID
				,lr.ToPartyID
		END
	END

	--2. For Licensees from Starlit and BA(FDL)
	IF EXISTS (
			SELECT 1
			FROM @tmpLicenseeReseller
			WHERE ToPartyID IN (
					SELECT PartyID
					FROM @tmpTable
					)
			)
	BEGIN
		INSERT INTO @data (
			Winlostdate
			,FromPartyID
			,ToPartyID
			,BetCount
			)
		SELECT b.rptDate
			,lr.FromPartyID
			,lr.ToPartyID
			,SUM(betcount) AS BetCount
		FROM #tmpBetting_BA b(NOLOCK)
		INNER JOIN @tmpLicenseeReseller lr ON b.siteID = lr.OldRefID
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd(NOLOCK) ON lr.FromPartyID = pd.PartyID
		WHERE pd.IsDeposit = 1
			AND b.rptDate BETWEEN lr.FromDate AND @ToDate
					--Licensees from Starlit, BA(FDL)
			AND lr.ToPartyID IN (
				SELECT PartyID
				FROM @tmpTable
				)
		GROUP BY b.rptDate
			,lr.FromPartyID
			,lr.ToPartyID
	END

	IF (@GroupBy = 1)
	BEGIN
		INSERT INTO @tmpTotalBet (
			GroupBy
			,ResellerID
			,ResellerName
			,LicenseeName
			,BetCount
			)
		SELECT CONVERT(VARCHAR(8), d.Winlostdate, 112) AS GroupBy
			,d.ToPartyID AS ResellerID
			,p.PartyName AS ResellerName
			,CASE 
				WHEN (
						r.ResellerType = 1
						OR p.PartyName = 'BA(FDL)'
						)
					THEN p1.PartyName
				ELSE ''
				END AS LicenseeName
			,ISNULL(SUM(d.BetCount), 0) AS BetCount
		FROM @data d
		INNER JOIN bodb_licensee.dbo.OAS_Party p(NOLOCK) ON d.ToPartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_Party p1(NOLOCK) ON d.FromPartyID = p1.PartyID
		INNER JOIN bodb_licensee.dbo.Resellers r(NOLOCK) ON r.ResellerID = p.OldRefID
		GROUP BY CONVERT(VARCHAR(8), d.winlostdate, 112)
			,d.ToPartyID
			,p.PartyName
			,CASE 
				WHEN (
						r.ResellerType = 1
						OR p.PartyName = 'BA(FDL)'
						)
					THEN p1.PartyName
				ELSE ''
				END
		ORDER BY CONVERT(VARCHAR(8), d.winlostdate, 112)
			,p.PartyName
			,CASE 
				WHEN (
						r.ResellerType = 1
						OR p.PartyName = 'BA(FDL)'
						)
					THEN p1.PartyName
				ELSE ''
				END
	END
	ELSE
	BEGIN
		INSERT INTO @tmpTotalBet (
			GroupBy
			,ResellerID
			,ResellerName
			,LicenseeName
			,BetCount
			)
		SELECT CONVERT(VARCHAR(6), d.Winlostdate, 112) AS GroupBy
			,d.ToPartyID AS ResellerID
			,p.PartyName AS ResellerName
			,CASE 
				WHEN (
						r.ResellerType = 1
						OR p.PartyName = 'BA(FDL)'
						)
					THEN p1.PartyName
				ELSE ''
				END AS LicenseeName
			,ISNULL(SUM(d.BetCount), 0) AS BetCount
		FROM @data d
		INNER JOIN bodb_licensee.dbo.OAS_Party p(NOLOCK) ON d.ToPartyID = p.PartyID
		INNER JOIN bodb_licensee.dbo.OAS_Party p1(NOLOCK) ON d.FromPartyID = p1.PartyID
		INNER JOIN bodb_licensee.dbo.Resellers r(NOLOCK) ON r.ResellerID = p.OldRefID
		GROUP BY CONVERT(VARCHAR(6), d.winlostdate, 112)
			,d.ToPartyID
			,p.PartyName
			,CASE 
				WHEN (
						r.ResellerType = 1
						OR p.PartyName = 'BA(FDL)'
						)
					THEN p1.PartyName
				ELSE ''
				END
		ORDER BY CONVERT(VARCHAR(6), d.winlostdate, 112)
			,p.PartyName
			,CASE 
				WHEN (
						r.ResellerType = 1
						OR p.PartyName = 'BA(FDL)'
						)
					THEN p1.PartyName
				ELSE ''
				END
	END

	--Add Total Cost
	SELECT tb.GroupBy
		,tb.ResellerID
		,tb.ResellerName
		,tb.LicenseeName
		,tb.BetCount
		,tb.BetCount * CONVERT(MONEY,ci.Rate) AS TotalCost
	FROM @tmpTotalBet tb
	INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci ON tb.ResellerID = ci.FromParty
		AND tb.BetCount BETWEEN ci.MinAmount AND ci.MaxAmount
     INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4
	WHERE @FromDate BETWEEN ci.FromDate AND ci.ToDate
     ORDER BY tb.ResellerName
	DROP TABLE #tmpBetting
	DROP TABLE #tmpBetting_BA
END
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_GetTotalTicket] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_Report_GetTotalTicket] TO bodbAdminNet 