set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go

ALTER    PROCEDURE [dbo].[OA_Get_ResellerProductCharge]      
@fromdate SMALLDATETIME,
@todate		SMALLDATETIME	
AS


  /*
Created: 20130121@Jim
Task : AllSites - RNG Casino Win Loss report
DB: DB052.bodb02

Revisions:
		-20130922@Jim:filter licensee/reseller list by date

*/
SELECT DISTINCT
	r.PartyID,
	P.PartyName,
	r.ResellerID,
	re.ResellerName,
	lr.LicenseeID,
	CASE WHEN l.LicenseeID=13 THEN 'ibcbet' 
	WHEN l.LicenseeID=18 THEN '1b88' 
	ELSE l.LicenseeName		
	END LicenseeName,	
	r.ChargeRate,
	r.FromDate,
	r.ToDate
FROM bodb_licensee.dbo.ResellerProductChargeByDateRange r WITH (NOLOCK)
	INNER JOIN bodb_licensee.dbo.LicenseeReseller lr WITH (NOLOCK) ON r.ResellerID=lr.ResellerID
	INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lr.LicenseeID=l.LicenseeID
	INNER JOIN bodb_licensee.dbo.Resellers re WITH (NOLOCK) ON re.ResellerID=lr.ResellerID
	INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd lp (NOLOCK) ON l.LicenseeID=lp.LicenseeID
	INNER JOIN bodb_licensee.dbo.Party p (NOLOCK) ON r.partyID=p.ID
WHERE r.ProductID=6
	AND (@todate >= r.FromDate and @fromdate<= r.ToDate)
	AND @todate >= Lp.EffectiveDate

/*
[OA_Get_ResellerProductCharge]      
@fromdate ='2013-01-01',
@todate		='2013-12-10'
*/
GO
GRANT EXECUTE ON [dbo].[OA_Get_ResellerProductCharge] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[OA_Get_ResellerProductCharge] TO [AccTeam]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Get_ResellerProductCharge] TO [vnteam]