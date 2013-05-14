 USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OA_Get_ResellerProductCharge]    Script Date: 01/22/2013 13:25:11 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER   PROCEDURE [dbo].[OA_Get_ResellerProductCharge]      
	
AS      
  /*
Created: 20130121@Jim
Task : AllSites - RNG Casino Win Loss report
DB: DB052.bodb02

Revisions:

*/
SELECT   ResellerID,
		 ResellerName,		
		 LicenseeID,
		 CASE WHEN LicenseeID=13 THEN 'ibcbet' 
			  WHEN LicenseeID=18 THEN '1b88' 
			  ELSE LicenseeName		
			  END LicenseeName,	
		[1] OneWorks ,
		[5] StarExpress 
FROM ( 	SELECT
		r.PartyID,
		r.ResellerID,
		re.ResellerName,
		lr.LicenseeID,
		l.LicenseeName,	
		r.ChargeRate

FROM bodb_licensee.dbo.ResellerProductChargeByDateRange r WITH (NOLOCK)
INNER JOIN bodb_licensee.dbo.LicenseeReseller lr WITH (NOLOCK) ON r.ResellerID=lr.ResellerID
INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lr.LicenseeID=l.LicenseeID
INNER JOIN bodb_licensee.dbo.Resellers re WITH (NOLOCK) ON re.ResellerID=lr.ResellerID
WHERE ProductID=6
)SourceTable 
PIVOT (MIN(ChargeRate ) FOR PartyID  IN ([1],[5])) PivotTable

GO
GRANT EXECUTE ON [dbo].[OA_Get_ResellerProductCharge] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[OA_Get_ResellerProductCharge] TO [AccTeam]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Get_ResellerProductCharge] TO [vnteam]


