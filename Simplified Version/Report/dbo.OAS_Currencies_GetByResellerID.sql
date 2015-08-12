   
  
ALTER PROCEDURE [dbo].[OAS_Currencies_GetByResellerID]    
 @ResellerID INT  
AS    
  
/*  
 * Created by : [20111512@Kos]  
 * Task  : Get all currencies of all licensees of a reseller  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 - 20141120@Winnie: change from LicenseeCust to f_SelLicenseeCust
 *   
 * Param's Explanation:    
 *  - @ResellerID : Reseller ID  
 */  
  
SET NOCOUNT ON  
  
DECLARE @temp AS TABLE (currency INT)  
  
INSERT INTO @temp  
SELECT DISTINCT Currency   
FROM   
	 dbo.f_SelLicenseeCust(0) lc --(NOLOCK)  
	 INNER JOIN  
	 LicenseeReseller lr (NOLOCK)  
	 ON lc.LicenseeID = lr.LicenseeID  
WHERE lr.ResellerID = @ResellerID  
  
SELECT   
	 t.currency,   
	 CASE   
	  WHEN t.currency = 20 THEN 'UUS'   
	  WHEN t.currency = 51 THEN 'INH'  
	  ELSE e.Code   
	 END AS CurrencyName  
FROM   
	 @temp t  
	 INNER JOIN   
	 bodb02.dbo.exchange e WITH (NOLOCK)   
	 ON t.currency = e.exchangeid  
ORDER BY   
	 CASE   
	  WHEN t.currency = 20 THEN 'UUS'   
	  WHEN t.currency = 51 THEN 'INH'  
	  ELSE e.Code   
	 END  
GO
GRANT EXECUTE ON [dbo].[OAS_Currencies_GetByResellerID] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Currencies_GetByResellerID] TO [vnteam]   
  
  
  