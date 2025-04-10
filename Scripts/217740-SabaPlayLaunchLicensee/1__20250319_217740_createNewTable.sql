/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20250319@Danny
	DB: DBLIC.bodb_licenseeReport
	Description: create new tables
*/



USE bodb_licenseeReport



CREATE TABLE SabaPlay_Operators 
(
	SiteID INT,
	SiteName NVARCHAR(200),
	OWSiteName NVARCHAR(50)
)

CREATE CLUSTERED INDEX [CIX_SabaPlay_Operators] ON [dbo].[SabaPlay_Operators]
(
	SiteID ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [LicenseeData]
GO



CREATE TABLE SabaPlay_Products
(
	ProductID SMALLINT,
	ProductName NVARCHAR(200)
)

CREATE CLUSTERED INDEX [CIX_SabaPlay_Products] ON [dbo].[SabaPlay_Products]
(
	ProductID ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [LicenseeData]
GO

