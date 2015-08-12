set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go


ALTER PROCEDURE [dbo].[OAS_TotalTrans_GetLicByResellerID]   
	@FromDate SMALLDATETIME,
	@ToDate   SMALLDATETIME,	
	@ResellerID INT = 0,
	@ExcludeBA BIT = 0,
	@ExcludeTest BIT = 1,
	@ProductCode VARCHAR(10)=''
AS  
  
/*  
 * Created by : [20131001@Victor]  
 * Task  : Get all licensees of a reseller for Total Trans report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
	- Previous: this SP is splitted to use for Total Trans page only from 'OAS_Licensees_GetByResellerID' 
	- 20130923@Victor: Starlit becomes FDL (BA) from Aug 1st 2013
	
 * Param's Explanation:    
 *  - @ResellerID : Reseller ID (0 : All reseller)  
 *	- @ExcludeBA: to exclude BA Licensees (Starlit)
 *	- @ExcludeTest: to exclude Spondemo (a test licensee)
 */  
  
SET NOCOUNT ON  
SELECT @Fromdate=ltrim(rtrim(@Fromdate)),@Todate=ltrim(rtrim(@Todate))

CREATE TABLE #Data (ResellerID int,ResellerName varchar(50), ResellerType INT,ResellerDescription varchar(100),LicenseeID INT, LicenseeName varchar(50),LicenseeDescription varchar(100))
DECLARE @ProductID INT
  
INSERT INTO #Data  (ResellerID,ResellerName, ResellerType,ResellerDescription,LicenseeID, LicenseeName,LicenseeDescription)
SELECT  
	r.ResellerID,  
	r.ResellerName,  
	r.ResellerType,
	r.Description AS ResellerDescription,  
	l.LicenseeID,  
	l.LicenseeName,
	l.Description AS LicenseeDescription
FROM   
	dbo.Licensees AS l WITH (NOLOCK)   
	INNER JOIN dbo.LicenseeReseller AS ls WITH (NOLOCK) ON l.LicenseeID = ls.LicenseeID AND (@ResellerID = 0 OR ls.ResellerID = @ResellerID)  
	INNER JOIN dbo.Resellers AS r WITH (NOLOCK)	ON r.ResellerID = ls.ResellerID  
	INNER JOIN SystemLicensee AS sl (NOLOCK) ON l.LicenseeID=sl.LicenseeID 
	INNER JOIN Systems AS s (NOLOCK) ON sl.SystemID=s.ID 
	LEFT JOIN dbo.LicenseeProduct3rd AS  ld WITH (NOLOCK) ON l.LicenseeID=ld.LicenseeID 
WHERE 
	(
		l.IsDeposit = 1  
		OR  
		(
			l.IsDeposit=0 AND l.LicenseeID IN (SELECT DISTINCT LicenseeID FROM Labels WITH (NOLOCK))
		)
	)
	AND sl.IsActive=1
	AND s.SystemName='OAS'
	AND ((@ExcludeBA=0) OR (@ExcludeBA=1 AND r.ResellerID <> 3))
	AND ((@ExcludeTest=0) OR (@ExcludeTest=1 AND r.ResellerID <> 6))
	AND (ISNULL(LTRIM(RTRIM(@ProductCode)),'')='' OR (ISNULL(LTRIM(RTRIM(@ProductCode)),''))<>'')
ORDER BY l.IsDeposit DESC,r.ResellerName, l.LicenseeName,EffectiveDate

SET @ProductCode = ISNULL(LTRIM(RTRIM(@ProductCode)),'')
IF @ProductCode <> '' AND EXISTS(SELECT 1 FROM Product3rd WITH (NOLOCK) WHERE ProductPrefix = @ProductCode)
BEGIN
	IF @ProductCode<> 'BA'
	BEGIN
		DELETE FROM #Data WHERE ResellerID = 3
		SELECT @ProductID = ProductID FROM Product3rd WITH (NOLOCK) WHERE ProductPrefix = @ProductCode
		
		DELETE FROM #Data 
		WHERE LicenseeID NOT IN (SELECT LicenseeID FROM LicenseeProduct3rd WITH (NOLOCK) WHERE ProductID=@ProductID AND ISNULL(EffectiveDate,0)<>0) 
		AND ResellerID NOT IN (4,8) --FDL, PIH
		
	END
	ELSE
	BEGIN
		DELETE FROM #Data WHERE ResellerID <> 3
	END

END

-- Remove Starlit, PIH, Boping, Cozni by date range
DELETE FROM #Data
WHERE (@FromDate BETWEEN '2013-07-01' AND '2013-07-31' AND ResellerID IN (3,8))
	  OR (@FromDate>='2013-08-01' AND ResellerID IN (5,7,8))

-- Remove direct licensees
DECLARE @DirectLics TABLE (ResellerID INT)

INSERT INTO @DirectLics
SELECT DISTINCT r.ResellerID 
FROM LicenseeReseller lr (NOLOCK)
	INNER JOIN Resellers r (NOLOCK) ON lr.ResellerID = r.ResellerID
	INNER JOIN Licensees l (NOLOCK) ON l.LicenseeID = lr.LicenseeID
WHERE 
	l.LicenseeName = r.ResellerName

DELETE FROM #Data WHERE ResellerID IN (SELECT ResellerID FROM @DirectLics)

SELECT DISTINCT ResellerID,
	CASE WHEN (ResellerID = 3 AND @FromDate>='2013-08-01') THEN 'BA (FDL)' ELSE ResellerName END AS ResellerName,
	ResellerType,
	ResellerDescription,
	LicenseeID,
	LicenseeName,
	LicenseeDescription
FROM #Data

DROP TABLE #Data

GO
GRANT EXECUTE ON [dbo].[OAS_TotalTrans_GetLicByResellerID] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_TotalTrans_GetLicByResellerID] TO [vnteam]        
GO


