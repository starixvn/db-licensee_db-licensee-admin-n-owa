USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OA_Rpt_GetTotalTicket_xtest]    Script Date: 06/10/2013 05:28:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_Rpt_GetTotalTicket_xtest    Script Date: 2013-06-05 4:42:56 PM ******/
ALTER PROCEDURE [dbo].[OA_Rpt_GetTotalTicket]    
	@NormalLicensee VARCHAR(1000),
	@BALicensee VARCHAR(1000),
	@FromDate		SMALLDATETIME,  
	@ToDate			SMALLDATETIME,  
	@showSB			BIT=1,
	@ShowRB			BIT=0,
	@ShowNG			BIT=0,
	@ShowLC			BIT=0,
	@ShowVS			BIT=0,
	@ShowCS			BIT=0,
	@SportID		INT=0,
	@bettype		INT=0,
	@ReportBy		TINYINT=0,  
	@GroupBy		TINYINT=1,  
	@UserID			INT,
	@Debug			BIT = 0
AS    
/*  Created: Henry    
 Date: 2011-09-22    
    Task : Get Total tickets of Licensees    
    DB: DB052.bodb02    
     
    Revisions:    
    - 20111107@Kos: add show racebook
    - 20111221@Henry: Only get data from sum table
    - 20120104@Henry: Enhance performance by using Dynamic Query
    - 20120221@Henry: FDL billing 222223, 733333, 222225, 722222, 755555, Indo from the 1st Feb 2012; 789y from the 1st March 2012
    - 20120301@Henry: Turn hard-code into table
    - 20120405@Henry: Get resellerID to calculate the rate
    - 20120515@Henry: exclude customercategory 28 - BARM
    - 20120816@Henry: add ShowLiveCasino 
    - 20120905@Henry: add Virtual Sports
	- 20130529@Jim:   add RNG Casino 
	- 20130531@Jim: fix bug wrong @fromdate variable  
	Param's Explanation:    
	+ @ReportBy 1-Live; 2-Non-Live; 0: All;  
	+ @GroupBy 1-Daily; 2-Monthly
	+ @showSB: Show SportsBook bets
	+ @ShowRB: Show RB bets
	+ @ShowNG: Show Number game bets
	+ @ShowLC: Show Live casino
	+ @ShowVS: Show Virtual Sports
	+ @ShowCS: Show RNG Casino 

  
*/    
BEGIN    


declare @sql varchar(MAX)

SELECT @sql = 'SET NOCOUNT ON  ' + char(13)



--declare
SELECT @sql = @sql + '--Declare variable:' + char(13)

SELECT @sql = @sql +	
				'DECLARE @data AS TABLE (WinlostDate SMALLDATETIME ,ResellerID INT,LicenseeID INT, betcount INT) ' + char(13) +
				'DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT ,LicenseeID INT,AffectedDate Datetime)' + char(13) +
				'DECLARE @i INT' + char(13) +
				'DECLARE @tempBettype AS TABLE (bettype INT PRIMARY KEY)' + char(13) 
				
		
--Get Licensee List
--1 Normal
IF LTRIM(RTRIM(ISNULL(@NormalLicensee,''))) <> ''
BEGIN
	SELECT @sql = @sql + '--Get normal licensee list:' + char(13)
	SELECT @sql = @sql + 
					'INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate)' + char(13) +
					'SELECT lr.ResellerID,lr.LicenseeID ,
					CASE WHEN '''+CONVERT(VARCHAR(10),@fromdate,120)+'''<=l.AffectedDate THEN l.AffectedDate ELSE '''+CONVERT(VARCHAR(10),@fromdate,120)+'''END '+ char(13) +
					'FROM bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)' + char(13) +
					'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID' + char(13) +
					'INNER JOIN ' + char(13) +
					'( ' + char(13) +
						'SELECT	gl.ResellerID,gl.LicenseeID ' + char(13) +
						'FROM bodb_Licensee.dbo.OA_GroupLicensees AS gl WITH(NOLOCK) ' + char(13) +
							'INNER JOIN bodb_Licensee.dbo.OA_Users AS u WITH(NOLOCK) ON gl.GroupID=u.GroupID AND u.UserID = ' + convert(varchar(20), @UserID) + char(13) +
						'UNION' + char(13) +
						'SELECT	ResellerID,LicenseeID ' + char(13) +
							'FROM bodb_Licensee.dbo.OA_UserLicensees WITH(NOLOCK)	' + char(13) +
						'WHERE UserID = ' + convert(varchar(20), @UserID)	+ char(13) +
					')  ulr ON lr.ResellerID = ulr.ResellerID AND lr.LicenseeID = ulr.LicenseeID'	+ char(13) +
					'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK ) ON ulr.LicenseeID=l.LicenseeID'+char(13)+
					'WHERE  r.ResellerID <> 3 AND' + char(13) +
					'		lr.LicenseeID IN (' + @NormalLicensee + ')'  + char(13) 
END
					
--2 BA Licensee
IF LTRIM(RTRIM(ISNULL(@BALicensee,''))) <> ''
BEGIN
    SELECT @sql = @sql + '--Get BA licensee list:' + char(13)
    SELECT @sql = @sql + 
                    'INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate)' + char(13) +
                    'SELECT lr.ResellerID,lr.LicenseeID ,
					CASE WHEN '''+CONVERT(VARCHAR(10),@fromdate,120)+'''<=l.AffectedDate THEN l.AffectedDate ELSE '''+CONVERT(VARCHAR(10),@fromdate,120)+'''END '+ char(13) +
					'FROM bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)' + char(13) +
                    'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID' + char(13) +
                    'INNER JOIN ' + char(13) +
                    '( ' + char(13) +
                        'SELECT    gl.ResellerID,gl.LicenseeID ' + char(13) +
                        'FROM bodb_Licensee.dbo.OA_GroupLicensees AS gl WITH(NOLOCK) ' + char(13) +
                        'INNER JOIN bodb_Licensee.dbo.OA_Users AS u WITH(NOLOCK) ON gl.GroupID=u.GroupID AND u.UserID = ' + convert(varchar(20), @UserID) + char(13) +
                        'UNION' + char(13) +
                        'SELECT    ResellerID,LicenseeID ' + char(13) +
                        'FROM bodb_Licensee.dbo.OA_UserLicensees WITH(NOLOCK)    ' + char(13) +
                        'WHERE UserID = ' + convert(varchar(20), @UserID)    + char(13) +
                    ')  ulr ON lr.ResellerID = ulr.ResellerID AND lr.LicenseeID = ulr.LicenseeID'    + char(13) +
					'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK ) ON ulr.LicenseeID=l.LicenseeID'+char(13)+
                    'WHERE  r.ResellerID = 3 AND' + char(13) +
                    '        lr.LicenseeID IN (' + @BALicensee + ')'  + char(13) 
END
				

--Get the data
SELECT @sql = @sql + '--Get the data:' + char(13)
IF (@ShowSB = 1 OR @ShowRB = 1 OR @ShowNG = 1 OR @ShowLC = 1 OR @ShowVS = 1 OR @ShowCS=1)
BEGIN
	--exclude BA & IBC & PIH...
	SELECT @sql = @sql + '--Exclude BA & IBC & PIH...:' + char(13)
	SELECT @sql = @sql + 
				'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr INNER JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid  WHERE l.IsDeposit=1 AND lr.ResellerID<>3)' + char(13) +
				'BEGIN' + char(13) +
					'INSERT INTO @data' + char(13) +
					'SELECT  b.rptDate,lr.ResellerID,lr.licenseeid, SUM(BetCount) AS betcount' + char(13) +
					'FROM @tmpLicenseeReseller lr' + char(13) +
						'INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid'+ char(13) +
						'INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID' + char(13) +
						'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
					'WHERE ' + char(13) +
						'b.rptDate BETWEEN lr.AffectedDate  AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
						'AND lr.ResellerID<>3' + char(13) + --BA
						'AND lic.isdeposit=1'+ char(13) +
						--'AND ''' + convert(varchar(10),@FromDate, 120) + ''' >= isnull(lic.AffectedDate,''1999-01-01'')' + char(13) +
						'AND b.status NOT IN (-1,103) ' + char(13) +
						'AND CurrencyID<>20 ' + char(13) +
						'AND (b.bettype < ' + CASE WHEN @ShowSB=1 THEN + ' 31 OR b.bettype BETWEEN 121 AND 999' ELSE '0' END +
						CASE WHEN @ShowRB = 1 THEN ' OR b.bettype BETWEEN 31 AND 33' ELSE '' END + 
						CASE WHEN @ShowLC = 1 THEN ' OR b.bettype BETWEEN 1101 AND 1199' ELSE '' END + 
						CASE WHEN @ShowVS = 1 THEN ' OR b.bettype BETWEEN 1201 AND 1299' ELSE '' END + 
						CASE WHEN @ShowCS = 1 THEN ' OR b.bettype =71 ' ELSE '' END + 
						CASE WHEN @ShowNG = 1 THEN ' OR b.bettype BETWEEN 81 AND 120' ELSE '' END + ')' + char(13) +
						CASE WHEN @bettype <> 0 THEN ' AND b.bettype = ' + convert(varchar(10), @Bettype)  ELSE '' END + char(13) +
						CASE WHEN @SportID<>0 THEN 'AND b.bettype NOT IN (9,29) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype = ' + convert(varchar(10), @SportID) ELSE '' END + char(13) +
						CASE 
							WHEN @ReportBy=1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
							WHEN @ReportBy=2 THEN 'AND b.IsLive=0 '
							ELSE '' END + char(13) +
						'GROUP BY b.rptDate,lr.ResellerID,lr.licenseeid ' + char(13) +							
				'END' + char(13) 
	--BA
	SELECT @sql = @sql + '--BA selection' + char(13)
	IF @ShowSB = 1
	BEGIN
		SELECT @sql = @sql + 
				'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller WHERE ResellerID = 3)' + char(13) +
				'BEGIN' + char(13) +
					'INSERT INTO @data' + char(13) +
					'SELECT b.rptDate, lr.ResellerID,lr.licenseeid, SUM(BetCount) AS betcount ' + char(13) +
					'FROM @tmpLicenseeReseller lr' + char(13) +
						'INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid'+ char(13) +
						'INNER JOIN bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID' + char(13) +
						'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
					'WHERE ' + char(13) +
						'b.rptDate BETWEEN lr.AffectedDate AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
						'AND lr.ResellerID=3'+ char(13) +
						'AND lic.isdeposit=1'+ char(13) +
						--'AND ''' + convert(varchar(10),@FromDate, 120) + ''' >= isnull(lic.AffectedDate,''1999-01-01'')' + char(13) +
						'AND b.status NOT IN (-1,103) ' + char(13) +
						'AND CurrencyID<>20 ' + char(13) +
						CASE WHEN @bettype<>0 THEN 'AND b.bettype = ' + convert(varchar(10), @Bettype)  ELSE '' END + char(13) +	
						CASE WHEN @SportID<>0 THEN 'AND b.bettype NOT IN (9,29)  AND l.Sporttype = ' + convert(varchar(10), @SportID)  ELSE '' END + char(13) +
						CASE 
							WHEN @ReportBy=1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10) '
							WHEN @ReportBy=2 THEN 'AND b.IsLive=0 '
							ELSE '' END + char(13) +
						'GROUP BY b.rptDate,lr.ResellerID,lr.licenseeid' + char(13) +
				'END' + char(13)
	END
	--FDL + PIH...
	SELECT @sql = @sql + '--FDL + PIH selection ...' + char(13)
	SELECT @sql = @sql + 
				'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)' + char(13) +
				'BEGIN' + char(13) +
					'INSERT INTO @data' + char(13) +
					'SELECT b.rptDate,lr.ResellerID,lr.LicenseeID ,SUM(BetCount) AS betcount' + char(13) +
					'FROM @tmpLicenseeReseller lr ' + char(13) +
					'INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID' + char(13) +
					'INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID' + char(13) +
						'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
					'WHERE ' + char(13) +
						'b.rptDate BETWEEN lr.AffectedDate AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
						'AND b.status NOT IN (-1,103) ' + char(13) +
						'AND lr.ResellerID<>3' + char(13) + --BA
						--'AND b.siteID IN (SELECT LicenseeID FROM @creditSite)' + char(13) +
						--'AND ''' + convert(varchar(10),@FromDate, 120) + ''' >= isnull(lb.AffectedDate,''1999-01-01'')' + char(13) +
						'AND CurrencyID<>20 ' + char(13) +
						'AND isnull(b.customercategory,-1) NOT IN (27,28) ' + char(13) +
						'AND (b.bettype < ' + CASE WHEN @ShowSB=1 THEN + ' 31 OR b.bettype BETWEEN 121 AND 999' ELSE '0' END +
						CASE WHEN @ShowRB = 1 THEN ' OR b.bettype BETWEEN 31 AND 33' ELSE '' END + 
						CASE WHEN @ShowLC = 1 THEN ' OR b.bettype BETWEEN 1101 AND 1199' ELSE '' END +
						CASE WHEN @ShowVS = 1 THEN ' OR b.bettype BETWEEN 1201 AND 1299' ELSE '' END +
						CASE WHEN @ShowCS = 1 THEN ' OR b.bettype =71' ELSE '' END +
						CASE WHEN @ShowNG = 1 THEN ' OR b.bettype BETWEEN 81 AND 120' ELSE '' END + ')' + char(13) +
						CASE WHEN @bettype <> 0 THEN ' AND b.bettype = ' + convert(varchar(10), @Bettype)  ELSE '' END + char(13) +
						CASE WHEN @SportID<>0 THEN 'AND b.bettype NOT IN (9,29) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype = ' + convert(varchar(10), @SportID)  ELSE '' END + char(13) +
						CASE 
							WHEN @ReportBy=1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
							WHEN @ReportBy=2 THEN 'AND b.IsLive=0 '
							ELSE '' END + char(13) +
						'GROUP BY b.rptDate,lr.ResellerID,lr.LicenseeID ' + char(13) +	
				'END' + char(13)
				
		
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
			
SELECT @sql = @sql + 
			'SELECT ' + char(13) +
				CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + ' GroupBy,' + char(13) +
				'r.ResellerID,r.ResellerName,l.LicenseeName,ISNULL(SUM(d.betcount),0) AS BetCount' + char(13) +	
			'FROM @data d ' + char(13) +	
				'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID' + char(13) +
				'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = d.LicenseeID' + char(13) +
			'GROUP BY ' + char(13) +
				CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + char(13) +
			',r.ResellerID,r.ResellerName, l.LicenseeName ' + char(13) +	
			'ORDER BY ' + char(13) +
			CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + char(13) +
			',r.ResellerName, l.LicenseeName ' + char(13) 

IF (@debug = 1) PRINT @sql
ELSE EXEC(@sql)

END

GO
GRANT EXECUTE ON [dbo].[OA_Rpt_GetTotalTicket] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Rpt_GetTotalTicket] TO [vnteam] 