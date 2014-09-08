USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_GetTotalTicket]    Script Date: 9/8/2014 5:12:24 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_GetTotalTicket] 
	 @PartyIDs VARCHAR(5500)
	,@FromDate SMALLDATETIME
	,@ToDate SMALLDATETIME	
	,@ProductCode varchar (10)
	,@SportType INT = 0
	,@BetType INT = 0
	,@ReportBy TINYINT = 0
	,@GroupBy TINYINT = 1
	,@UserID INT
	,@Debug BIT = 0
AS
/*  Created: Florent.Nguyen    
 Date: 2014-09-03    
    Task : Get Total tickets of Licensees    
    DB: DB052.bodb02    
    Base on :[OA_Rpt_GetTotalTicket]
     
    Revisions:    
    
	Param's Explanation:    
	+ @ReportBy 1-Live; 2-Non-Live; 0: All;  
	+ @GroupBy 1-Daily; 2-Monthly

  
*/
BEGIN
	DECLARE @sql VARCHAR(MAX)

	SELECT @sql = 'SET NOCOUNT ON  ' + CHAR(13)

	--declare
	SELECT @sql = @sql + '--Declare variable:' + CHAR(13)

	SELECT @sql = @sql + 'DECLARE @data AS TABLE (WinlostDate SMALLDATETIME ,ResellerID INT,LicenseeID INT, betcount INT) ' + CHAR(13) + 'DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT ,LicenseeID INT,AffectedDate Datetime)' + CHAR(13) + 'DECLARE @i INT' + CHAR(13) + 'DECLARE @tempBettype AS TABLE (bettype INT PRIMARY KEY)' + CHAR(13)

	--Parse from PartyID to LicenseeID
	DECLARE @NormalLicensee VARCHAR (5500) =''
	SELECT @NormalLicensee = @NormalLicensee + CONVERT(varchar(10), p.OldRefID) + ','
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) 
	WHERE p.PartyID in (SELECT val FROM dbo.strSplit(@PartyIDs,','))
	AND p.PartyType = 1
	SELECT @NormalLicensee = SUBSTRING(@NormalLicensee,0,len(@NormalLicensee))
	--Get Licensee List
	--1 Normal
	IF LTRIM(RTRIM(ISNULL(@NormalLicensee, ''))) <> ''
	BEGIN
		SELECT @sql = @sql + '--Get normal licensee list:' + CHAR(13)

		SELECT @sql = @sql + 'INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate)' + CHAR(13) + 'SELECT lr.ResellerID,lr.LicenseeID ,
					CASE WHEN ''' + CONVERT(VARCHAR(10), @fromdate, 120) + '''<=l.AffectedDate THEN l.AffectedDate ELSE ''' + CONVERT(VARCHAR(10), @fromdate, 120) + '''END ' + CHAR(13) + 'FROM bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)' + CHAR(13) + 'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID' + CHAR(13) + 'INNER JOIN ' + CHAR(13) + '( ' + CHAR(13) + 'SELECT	gl.ResellerID,gl.LicenseeID ' + CHAR(13) + 'FROM bodb_Licensee.dbo.OA_GroupLicensees AS gl WITH(NOLOCK) ' + CHAR(13) + 'INNER JOIN bodb_Licensee.dbo.OA_Users AS u WITH(NOLOCK) ON gl.GroupID=u.GroupID AND u.UserID = ' + convert(VARCHAR(20), @UserID) + CHAR(13) + 'UNION' + CHAR(13) + 'SELECT	ResellerID,LicenseeID ' + CHAR(13) + 'FROM bodb_Licensee.dbo.OA_UserLicensees WITH(NOLOCK)	' + CHAR(13) + 'WHERE UserID = ' + convert(VARCHAR(20), @UserID) + CHAR(13) + 
			')  ulr ON lr.ResellerID = ulr.ResellerID AND lr.LicenseeID = ulr.LicenseeID' + CHAR(13) + 'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK ) ON ulr.LicenseeID=l.LicenseeID' + CHAR(13) + 'WHERE  r.ResellerID <> 3 AND' + CHAR(13) + '		lr.LicenseeID IN (' + @NormalLicensee + ')' + CHAR(13)
	END

	--2 BA Licensee
	--IF LTRIM(RTRIM(ISNULL(@BALicensee, ''))) <> ''
	--BEGIN
	--	SELECT @sql = @sql + '--Get BA licensee list:' + CHAR(13)

	--	SELECT @sql = @sql + 'INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate)' + CHAR(13) + 'SELECT lr.ResellerID,lr.LicenseeID ,
	--				CASE WHEN ''' + CONVERT(VARCHAR(10), @fromdate, 120) + '''<=l.AffectedDate THEN l.AffectedDate ELSE ''' + CONVERT(VARCHAR(10), @fromdate, 120) + '''END ' + CHAR(13) + 'FROM bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)' + CHAR(13) + 'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID' + CHAR(13) + 'INNER JOIN ' + CHAR(13) + '( ' + CHAR(13) + 'SELECT    gl.ResellerID,gl.LicenseeID ' + CHAR(13) + 'FROM bodb_Licensee.dbo.OA_GroupLicensees AS gl WITH(NOLOCK) ' + CHAR(13) + 'INNER JOIN bodb_Licensee.dbo.OA_Users AS u WITH(NOLOCK) ON gl.GroupID=u.GroupID AND u.UserID = ' + convert(VARCHAR(20), @UserID) + CHAR(13) + 'UNION' + CHAR(13) + 'SELECT    ResellerID,LicenseeID ' + CHAR(13) + 'FROM bodb_Licensee.dbo.OA_UserLicensees WITH(NOLOCK)    ' + CHAR(13) + 'WHERE UserID = ' + convert(VARCHAR(20), @UserID) + CHAR(13) + 
	--		')  ulr ON lr.ResellerID = ulr.ResellerID AND lr.LicenseeID = ulr.LicenseeID' + CHAR(13) + 'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK ) ON ulr.LicenseeID=l.LicenseeID' + CHAR(13) + 'WHERE  r.ResellerID = 3 AND' + CHAR(13) + '        lr.LicenseeID IN (' + @BALicensee + ')' + CHAR(13)
	--END

	--Get the data
	SELECT @sql = @sql + '--Get the data:' + CHAR(13)
		
	BEGIN
		--exclude BA & IBC & PIH...
		SELECT @sql = @sql + '--Exclude BA & IBC & PIH...:' + CHAR(13)

		SELECT @sql = @sql + 'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr INNER JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid  WHERE l.IsDeposit=1 AND lr.ResellerID<>3)' + CHAR(13) + 'BEGIN' + CHAR(13) + 'INSERT INTO @data' + CHAR(13) + 'SELECT  b.rptDate,lr.ResellerID,lr.licenseeid, SUM(BetCount) AS betcount' + CHAR(13) + 'FROM @tmpLicenseeReseller lr' + CHAR(13) + 'INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid' + CHAR(13) + 'INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID' + CHAR(13) + 'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + CHAR(13) + 'WHERE ' + CHAR(13) + 'b.rptDate BETWEEN lr.AffectedDate  AND ''' + convert(VARCHAR(10), @ToDate, 120) + '''' + CHAR(13) + 'AND lr.ResellerID<>3' + CHAR(13) + --BA
			'AND lic.isdeposit=1' + CHAR(13) +
			--'AND ''' + convert(varchar(10),@FromDate, 120) + ''' >= isnull(lic.AffectedDate,''1999-01-01'')' + char(13) +
			'AND b.status NOT IN (-1,103) ' + CHAR(13) + 'AND CurrencyID<>20 ' + CHAR(13) + 'AND (b.bettype < ' + CASE 
				WHEN @ProductCode = 'SB'
					THEN + ' 31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 1301 AND 1399'
				ELSE '0'
				END + CASE 
				WHEN @ProductCode = 'RB'
					THEN ' OR b.bettype BETWEEN 31 AND 33'
				ELSE ''
				END + CASE 
				WHEN @ProductCode = 'LC'
					THEN ' OR b.bettype BETWEEN 1101 AND 1199'
				ELSE ''
				END + CASE 
				WHEN @ProductCode = 'VS'
					THEN ' OR b.bettype BETWEEN 1201 AND 1299'
				ELSE ''
				END + CASE 
				WHEN @ProductCode = 'CS'
					THEN ' OR b.bettype =71 '
				ELSE ''
				END + CASE 
				WHEN @ProductCode = 'NG'
					THEN ' OR b.bettype BETWEEN 81 AND 120'
				ELSE ''
				END + ')' + CHAR(13) + CASE 
				WHEN @bettype <> 0
					THEN ' AND b.bettype = ' + convert(VARCHAR(10), @Bettype)
				ELSE ''
				END + CHAR(13) + CASE 
				WHEN @Sporttype <> 0
					THEN 'AND b.bettype NOT IN (9,29) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype = ' + convert(VARCHAR(10), @SportType)
				ELSE ''
				END + CHAR(13) + CASE 
				WHEN @ReportBy = 1
					THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
				WHEN @ReportBy = 2
					THEN 'AND b.IsLive=0 '
				ELSE ''
				END + CHAR(13) + 'GROUP BY b.rptDate,lr.ResellerID,lr.licenseeid ' + CHAR(13) + 'END' + CHAR(13)

		--BA
		--SELECT @sql = @sql + '--BA selection' + CHAR(13)

		--IF @ShowSB = 1
		--BEGIN
		--	SELECT @sql = @sql + 'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller WHERE ResellerID = 3)' + CHAR(13) + 'BEGIN' + CHAR(13) + 'INSERT INTO @data' + CHAR(13) + 'SELECT b.rptDate, lr.ResellerID,lr.licenseeid, SUM(BetCount) AS betcount ' + CHAR(13) + 'FROM @tmpLicenseeReseller lr' + CHAR(13) + 'INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid' + CHAR(13) + 'INNER JOIN bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID' + CHAR(13) + 'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + CHAR(13) + 'WHERE ' + CHAR(13) + 'b.rptDate BETWEEN lr.AffectedDate AND ''' + convert(VARCHAR(10), @ToDate, 120) + '''' + CHAR(13) + 'AND lr.ResellerID=3' + CHAR(13) + 'AND lic.isdeposit=1' + CHAR(13) +
		--		--'AND ''' + convert(varchar(10),@FromDate, 120) + ''' >= isnull(lic.AffectedDate,''1999-01-01'')' + char(13) +
		--		'AND b.status NOT IN (-1,103) ' + CHAR(13) + 'AND CurrencyID<>20 ' + CHAR(13) + CASE 
		--			WHEN @bettype <> 0
		--				THEN 'AND b.bettype = ' + convert(VARCHAR(10), @Bettype)
		--			ELSE ''
		--			END + CHAR(13) + CASE 
		--			WHEN @SportID <> 0
		--				THEN 'AND b.bettype NOT IN (9,29)  AND l.Sporttype = ' + convert(VARCHAR(10), @SportID)
		--			ELSE ''
		--			END + CHAR(13) + CASE 
		--			WHEN @ReportBy = 1
		--				THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10) '
		--			WHEN @ReportBy = 2
		--				THEN 'AND b.IsLive=0 '
		--			ELSE ''
		--			END + CHAR(13) + 'GROUP BY b.rptDate,lr.ResellerID,lr.licenseeid' + CHAR(13) + 'END' + CHAR(13)
		--END

		--FDL + PIH...
		SELECT @sql = @sql + '--FDL + PIH selection ...' + CHAR(13)

		SELECT @sql = @sql + 'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)' + CHAR(13) + 'BEGIN' + CHAR(13) + 'INSERT INTO @data' + CHAR(13) + 'SELECT b.rptDate,lr.ResellerID,lr.LicenseeID ,SUM(BetCount) AS betcount' + CHAR(13) + 'FROM @tmpLicenseeReseller lr ' + CHAR(13) + 'INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID' + CHAR(13) + 'INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID' + CHAR(13) + 'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + CHAR(13) + 'WHERE ' + CHAR(13) + 'b.rptDate BETWEEN lr.AffectedDate AND ''' + convert(VARCHAR(10), @ToDate, 120) + '''' + CHAR(13) + 'AND b.status NOT IN (-1,103) ' + CHAR(13) + 'AND lr.ResellerID<>3' + CHAR(13) + --BA
			--'AND b.siteID IN (SELECT LicenseeID FROM @creditSite)' + char(13) +
			--'AND ''' + convert(varchar(10),@FromDate, 120) + ''' >= isnull(lb.AffectedDate,''1999-01-01'')' + char(13) +
			'AND CurrencyID<>20 ' + CHAR(13) + 'AND isnull(b.customercategory,-1) NOT IN (27,28) ' + CHAR(13) + 'AND (b.bettype < ' + CASE 
				WHEN @ProductCode = 'SB'
					THEN + ' 31 OR b.bettype BETWEEN 121 AND 999'
				ELSE '0'
				END + CASE 
				WHEN @ProductCode = 'RB'
					THEN ' OR b.bettype BETWEEN 31 AND 33'
				ELSE ''
				END + CASE 
				WHEN @ProductCode = 'LC'
					THEN ' OR b.bettype BETWEEN 1101 AND 1199'
				ELSE ''
				END + CASE 
				WHEN @ProductCode = 'VS'
					THEN ' OR b.bettype BETWEEN 1201 AND 1299'
				ELSE ''
				END + CASE 
				WHEN @ProductCode = 'CS'
					THEN ' OR b.bettype =71'
				ELSE ''
				END + CASE 
				WHEN @ProductCode = 'NG'
					THEN ' OR b.bettype BETWEEN 81 AND 120'
				ELSE ''
				END + ')' + CHAR(13) + CASE 
				WHEN @bettype <> 0
					THEN ' AND b.bettype = ' + convert(VARCHAR(10), @Bettype)
				ELSE ''
				END + CHAR(13) + CASE 
				WHEN @SportType <> 0
					THEN 'AND b.bettype NOT IN (9,29) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype = ' + convert(VARCHAR(10), @SportType)
				ELSE ''
				END + CHAR(13) + CASE 
				WHEN @ReportBy = 1
					THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
				WHEN @ReportBy = 2
					THEN 'AND b.IsLive=0 '
				ELSE ''
				END + CHAR(13) + 'GROUP BY b.rptDate,lr.ResellerID,lr.LicenseeID ' + CHAR(13) + 'END' + CHAR(13)
	END

	--Show data
	/*
SELECT @sql = @sql + '--Show the data' + char(13)
SELECT @sql = @sql + 
			'SELECT ' + char(13) +
				CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + ' GroupBy,' + char(13) +
				'ISNULL(SUM(d.betcount),0) AS BetCount ' + char(13) +
			'FROM @data d ' + char(13) +	
			'GROUP BY ' + char(13) +	
				CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + char(13) +
			'ORDER BY GroupBy' + char(13) 
*/
	SELECT @sql = @sql + 'SELECT ' + CHAR(13) + CASE 
			WHEN @GroupBy = 1
				THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) '
			WHEN @GroupBy = 2
				THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
			END + ' GroupBy,' + CHAR(13) + 'r.ResellerID,r.ResellerName,l.LicenseeName,ISNULL(SUM(d.betcount),0) AS BetCount' + CHAR(13) + 'FROM @data d ' + CHAR(13) + 'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID' + CHAR(13) + 'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = d.LicenseeID' + CHAR(13) + 'GROUP BY ' + CHAR(13) + CASE 
			WHEN @GroupBy = 1
				THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) '
			WHEN @GroupBy = 2
				THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
			END + CHAR(13) + ',r.ResellerID,r.ResellerName, l.LicenseeName ' + CHAR(13) + 'ORDER BY ' + CHAR(13) + CASE 
			WHEN @GroupBy = 1
				THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) '
			WHEN @GroupBy = 2
				THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
			END + CHAR(13) + ',r.ResellerName, l.LicenseeName ' + CHAR(13)

	IF (@debug = 1)
		PRINT @sql
	ELSE
		EXEC (@sql)
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_GetTotalTicket] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_GetTotalTicket] TO bodbAdminNet 

