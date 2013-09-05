set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go


ALTER PROCEDURE [dbo].[OAS_Licensees_GetByResellerID]   
	@FromDate SMALLDATETIME,
	@ToDate   SMALLDATETIME,	
	@ResellerID INT = 0,
	@ExcludeBA BIT = 0,
	@ExcludeTest BIT = 1,
	@ProductCode VARCHAR(10)=''
AS  
  
/*  
 * Created by : [20111220@Kos]  
 * Task  : Get all licensees of a reseller  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
	- 20120319@Henry: hard-code Boping to not show 
	- 20120510@Henry: only get licensees which have IsOneWorkActive=1
	- 20120621@Jim: optimize code 
	- 20120828@Henry: add 2 more params @ExcludeBA and @ExcludeTest
	- 20120917@Henry: add param @ProductCode
	- 20130222@Scott: add filter LicenseeProduct3rd.EffectiveDate <> null
	- 20130621@Jim: fix bug wrong conditiion when inner join with table licenseeProduct3rd
	- 20130724@Jim:  PIH and Starlit are no longer ONEWorks licensees since July 1st 2013
	- 20130730@Jim: fix bug (exclude all licensee whose EffectiveDate is null )
	- 20130905@Jim:Boping is no longer ONEWorks licensee since August 1st 2013
	
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
DELETE FROM #Data
WHERE (@FromDate BETWEEN '2013-07-01' AND '2013-07-31' AND ResellerID IN (3,8))
	  OR (@FromDate>='2013-08-01' AND ResellerID IN (3,7,8))

SELECT DISTINCT * FROM #Data

DROP TABLE #Data

GO
GRANT EXECUTE ON [dbo].[OAS_Licensees_GetByResellerID] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Licensees_GetByResellerID] TO [vnteam]        
  


