set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go

 ALTER   PROCEDURE [dbo].[OAS_Report_GetTotalTicket]      
	@NormalLicensee VARCHAR(1000),  
	@Operator  VARCHAR(1000),  
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME,    
	@SportID  INT    = 0,  
	@GroupBy  TINYINT   = 1,
	@Debug			BIT = 0
AS      
  
/*  
 * Created by : [20111219@Kos]  
 * Task  : Get total tickets of operators and licensees  
 * DB   : DB052.bodb02  
 * Revisions :  
 *  20120221@Henry: FDL billing 222223, 733333, 222225, 722222, 755555, Indo from the 1st Feb 2012; 789y from the 1st March 2012
	20120302@Henry: Turn hard-code into table
	20120405@Henry: Get resellerID to calculate the rate
	20120515@Henry: exclude customercategory 28 - BARM
	20120704@Henry: Map Licensee with System
	20130531@Jim: fix bug wrong @fromdate variable
	20130724@Jim:  PIH and Starlit are no longer ONEWorks licensees since July 1st 2013
	20130721@Jim: improve performance 
	20130830@Jim: Remove Cozni from licensee list in Total Transaction report from 1st August 2013.
	20130905@Jim: Boping is no longer ONEWorks licensee since August 1st 2013
	20130923@Victor: BA belongs to FDL from Aug 1st 2013 (except Boping BAs)
 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','  
 *  - @FromDate   : From date   
 *  - @ToDate   : To date  
 *  - @SportID   : Sport type ID  
 *  - @bettype   : Bet type ID  
 *  - @ReportBy   : 0 : All, 1 : Live, 2 : Non-live  
 *  - @GroupBy   : 1 : Daily, 2 : Monthly  
 */  
    
BEGIN     

declare @sql varchar(8000)
SELECT @sql = 'SET NOCOUNT ON  ' + char(13)

--declare
SELECT @sql = @sql + '--Declare variable:' + char(13)

SELECT @sql = @sql +	
				'DECLARE @data AS TABLE (WinlostDate SMALLDATETIME, ResellerID INT, LicenseeID INT, betcount INT)  ' + char(13) +
				'DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT, LicenseeID INT,AffectedDate Datetime) ' + char(13) 
				
SELECT @sql = @sql +'CREATE TABLE #tmpBetting(rptDate datetime,siteID INT,betcount INT)'+char(13)
SELECT @sql = @sql +'/* improve performance */
					INSERT INTO  #tmpBetting(rptDate,siteID,betcount)'+char(13)+
					'SELECT b.rptDate,b.SiteID,SUM(b.betcount)'+char(13)+
					'FROM bodb_licensee.dbo.rpt_betting b WITH (NOLOCK)'+char(13)+
						'LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.leagueid=l.leagueid'+char(13)+
					'WHERE b.rptDate >= ''' + CONVERT(varchar(10),@FromDate, 120) + ''' AND rptDate <= ''' + CONVERT(varchar(10),@ToDate, 120) + ''''+char(13)+ 
						'AND b.status NOT IN (-1,103)'+char(13)+
						 'AND b.CurrencyID<>20'+char(13)+ 
						 'AND ISNULL(b.CustomerCategory,0) not in (27,28)'+char(13)+
						 'AND (b.bettype<31 OR b.bettype BETWEEN 121 AND 999)' + char(13)+
					CASE WHEN @SportID<>0 THEN 'AND b.bettype NOT IN (9,29) AND l.Sporttype = ' + convert(varchar(10), @SportID)  ELSE '' END + char(13)+
						'GROUP BY b.rptDate,b.SiteID
						/* End improve */'
					
-- Normal licensees  
IF LTRIM(RTRIM(ISNULL(@NormalLicensee,''))) <> ''
BEGIN
	SELECT @sql = @sql + '--Get normal licensee list:' + char(13)
	SELECT @sql = @sql +
					'INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate) ' + char(13) +
					'SELECT lr.ResellerID,lr.LicenseeID ,
					CASE WHEN '''+CONVERT(VARCHAR(10),@fromdate,120)+'''<=l.AffectedDate THEN l.AffectedDate ELSE '''+CONVERT(VARCHAR(10),@fromdate,120)+'''END '+ char(13) +
					'FROM'+ char(13) +
						'bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)'+ char(13) +
						'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lr.LicenseeID=l.LicenseeID'+char(13)+
						'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID' + char(13) +
					'WHERE' + char(13) +
						'r.ResellerID <> 3 AND' + char(13) +
						'lr.LicenseeID IN (' + @NormalLicensee + ')' + char(13) 
END

-- Operator
IF LTRIM(RTRIM(ISNULL(@Operator,''))) <> ''
BEGIN
	SELECT @sql = @sql + '--Get Operator list:' + char(13)
	SELECT @sql = @sql + 
					'INSERT INTO @tmpLicenseeReseller (ResellerID, LicenseeID,AffectedDate)   ' + char(13) +
					'SELECT lr.ResellerID, lr.LicenseeID   ,
							CASE WHEN  '''+CONVERT(VARCHAR(10),@fromdate,120)+'''<=l.AffectedDate THEN l.AffectedDate ELSE '''+CONVERT(VARCHAR(10),@fromdate,120)+'''END'+ char(13) +
					'FROM ' + char(13) +
						'bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)' + char(13) +
						'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lr.LicenseeID=l.LicenseeID'+char(13)+
						'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID' + char(13) +
					'WHERE ' + char(13) +
						'r.ResellerID IN (' + @Operator + ')' + char(13) 
END
SELECT @sql = @sql +
'DELETE FROM @tmpLicenseeReseller 
WHERE (
		('''+convert(varchar(10),@Fromdate,120)+'''BETWEEN ''2013-07-01'' AND ''2013-07-31''  AND ResellerID IN (3,8) ) OR ('''+convert(varchar(10),@Fromdate,120)+'''>=''2013-08-01'' AND ResellerID in (5,7,8 ))
		)'+char(13)

--exclude BA & IBC & PIH...
SELECT @sql = @sql + '--Exclude BA & IBC & PIH...' + char(13)
SELECT @sql = @sql + 
				'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr INNER JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid  WHERE l.IsDeposit=1 AND lr.ResellerID<>3)' + char(13) +
				'BEGIN' + char(13) +
					'INSERT INTO @data' + char(13) +
					'SELECT  b.rptDate,lr.ResellerID,lr.licenseeid, SUM(BetCount) AS betcount ' + char(13) +
					'FROM @tmpLicenseeReseller lr' + char(13) +
						'INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid'+ char(13) +
						'INNER JOIN #tmpBetting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID' + char(13) +
						'INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON lic.LicenseeID=sl.LicenseeID ' + char(13) +
						'INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID '+ char(13) +
					'WHERE' + char(13) +
						'b.rptDate BETWEEN  lr.AffectedDate  AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
						'AND lr.ResellerID<>3' + char(13) + --BA
						'AND lic.isdeposit=1'+ char(13) +
						'AND sl.IsActive = 1' + char(13) +
						'AND s.SystemName=''OAS''' + char(13) +
					'GROUP BY b.rptDate, lr.ResellerID, lr.licenseeid' + char(13) +
				'END' + char(13) 

-- Remove Boping licensees from BA (FDL) licensees
IF (@FromDate >= CAST('2013-08-01' AS SMALLDATETIME))
BEGIN
	SELECT @sql = @sql +	'DELETE FROM @tmpLicenseeReseller' + CHAR(13) +
							'WHERE LicenseeID IN (SELECT lr1.LicenseeID ' + CHAR(13) +
												'FROM bodb_licensee.dbo.LicenseeReseller lr1 (NOLOCK) ' + CHAR(13) +
												'WHERE lr1.ResellerID IN (7)) AND ResellerID = 3' + CHAR(13)
END
--BA
SELECT @sql = @sql + '--BA selection' + char(13)
SELECT @sql = @sql + 
				'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller WHERE ResellerID = 3)' + char(13) +
				'BEGIN' + char(13) +
					'INSERT INTO @data' + char(13) +
					'SELECT b.rptDate, lr.ResellerID,lr.licenseeid, SUM(BetCount) AS betcount' + char(13) +
					'FROM @tmpLicenseeReseller lr' + char(13) +
						'INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid'+ char(13) +
						'INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON lic.LicenseeID=sl.LicenseeID ' + char(13) +
						'INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID '+ char(13) +
						'INNER JOIN bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID' + char(13) +
						'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
					'WHERE' + char(13) +
						'b.rptDate BETWEEN lr.AffectedDate AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
						'AND lr.ResellerID=3'+ char(13) +
						'AND lic.isdeposit=1'+ char(13) +
						'AND sl.IsActive = 1' + char(13) +
						'AND s.SystemName=''OAS''' + char(13) +
						'AND b.status NOT IN (-1,103) ' + char(13) +
						'AND CurrencyID<>20 ' + char(13) +
						CASE WHEN @SportID<>0 THEN 'AND b.bettype NOT IN (9,29)  AND l.Sporttype = ' + convert(varchar(10), @SportID)  ELSE '' END + char(13) +
											
					'GROUP BY b.rptDate, lr.ResellerID, lr.licenseeid' + char(13) +
				'END' + char(13) 
				
--FDL + PIH...
SELECT @sql = @sql + '--FDL + PIH selection ...' + char(13)
SELECT @sql = @sql + 				
				'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)' + char(13) +
				'BEGIN' + char(13) +
					'INSERT INTO @data' + char(13) +
					'SELECT b.rptDate,lr.ResellerID,lr.LicenseeID ,SUM(BetCount) AS betcount' + char(13) +
					'FROM @tmpLicenseeReseller lr ' + char(13) +
						'INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID' + char(13) +
						'INNER JOIN #tmpBetting b WITH ( NOLOCK) ON b.siteID=lb.LabelID' + char(13) +
					'WHERE' + char(13) +	
						'b.rptDate BETWEEN lr.AffectedDate AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
						'AND lr.ResellerID<>3' + char(13) + --BA
					'GROUP BY b.rptDate,lr.ResellerID,lr.LicenseeID ' + char(13) +	
				'END' + char(13) 

SELECT @sql = @sql + 
			'SELECT ' + char(13) +
				CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + ' GroupBy,' + char(13) +
				'r.ResellerID,' + CHAR(13) +
				'CASE WHEN (r.ResellerID = 3 AND CAST('''+CAST(@FromDate AS VARCHAR)+''' AS SMALLDATETIME)>=''2013-08-01'') THEN ''BA (FDL)'' ELSE r.ResellerName END AS ResellerName,' + char(13) +
				'CASE WHEN r.ResellerType = 2 THEN '''' ELSE l.LicenseeName END AS LicenseeName,' + char(13) +
				'ISNULL(SUM(d.betcount), 0) AS BetCount' + char(13) +
			'FROM' + char(13) +
				'@data d ' + char(13) +
				'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID  ' + char(13) +
				'LEFT JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = d.LicenseeID ' + char(13) +
			'GROUP BY ' + char(13) +
			CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + char(13) +
			' ,r.ResellerID,r.ResellerName, CASE WHEN r.ResellerType = 2 THEN '''' ELSE l.LicenseeName END ' + char(13) +
			'ORDER BY ' + char(13) +
			CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + char(13) +
			',r.ResellerName, CASE WHEN r.ResellerType = 2 THEN '''' ELSE l.LicenseeName END'+char(13)
			
SELECT @sql = @sql +'DROP TABLE #tmpBetting'	
IF (@debug = 1) PRINT @sql
ELSE EXEC(@sql)
  
END  
GO
GRANT EXECUTE ON [dbo].[OAS_Report_GetTotalTicket] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_GetTotalTicket] TO [vnteam]   
