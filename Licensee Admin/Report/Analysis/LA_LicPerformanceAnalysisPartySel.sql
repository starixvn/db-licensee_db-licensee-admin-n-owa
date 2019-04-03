/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].LA_LicPerformanceAnalysisPartySel (
	@PathCode VARCHAR(50) = '/'
)
AS
/*  Created: 20190306@Bruce
	Task : Get party & group info for licensee performance analysis report
	DB: DBLIC.bodb_Licensee
	Revisions:
		- 20190306@Bruce: Create SP
*/
BEGIN
	;WITH cte_Group AS (
		SELECT a.GroupId,
			ISNULL(b.GroupId,a.GroupId) AS ParentId,
			ISNULL(b.GroupName,a.GroupName) AS GroupName
		FROM dbo.LA_CombinedGroup a WITH(NOLOCK)
		LEFT JOIN dbo.LA_CombinedGroup b WITH(NOLOCK) ON a.PathCode LIKE ('%/' + CAST(b.GroupId AS VARCHAR(5)) + '/%')
		WHERE a.PathCode LIKE (@PathCode + '%')
	),
	cte_LaunchDate AS (
		SELECT p.PartyID, p.OldRefID, p.PartyName, d.BrandName, MIN(i.FromDate) AS LaunchDate
		FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_ChargeInfo i WITH(NOLOCK) ON p.PartyID = i.FromParty
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
		WHERE p.PartyType = 1
		GROUP BY p.PartyID, p.OldRefID, p.PartyName, d.BrandName
	)
	SELECT l.LicenseeID AS SiteId, 
		l.LicenseeName,
		p.PartyName,
		p.BrandName,
		g.ParentId AS GroupId,
		g.GroupName,
		CASE WHEN p.PartyID IS NULL THEN 0 ELSE 1 END AS IsLaunched,
		CASE WHEN p.PartyID IS NULL THEN NULL ELSE ISNULL(l.AffectedDate, p.LaunchDate) END AS LaunchDate
	FROM dbo.Licensees l WITH(NOLOCK)
	LEFT JOIN cte_LaunchDate p WITH(NOLOCK) ON p.OldRefID = l.LicenseeID
	LEFT JOIN dbo.LA_CombinedGroupAssignment a WITH(NOLOCK) ON p.PartyID = a.PartyId
	LEFT JOIN cte_Group g ON g.GroupId = a.GroupId
	WHERE l.IsDeposit = 1
END