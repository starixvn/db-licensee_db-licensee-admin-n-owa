/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

CREATE PROCEDURE dbo.LA_VendorPaymentProductListSel
AS
/*  
	Created: 20220324@Danny
	Task : Get all vendor products
	DB: DBLIC.bodb_Licensee
	
	Revisions:     
		- 20220324@Danny: Create SP [RedmineID: #168387]

	/* Vendor:
		2	Number Game
		5	Virtual Sports
		8	RNG Keno
		10	AG Casino
		15	Colossus Bets
		21	Allbet
		22	Macau Games
		23	Number Game 2
		24	Fishing World
		25	Cash Out
		27	Virtual Sports 2
		28	Lottery
		31	Exchange
		32	Pragmatic
		34	Arcadia Gaming
		36	SG
		39	SA Gaming
		40	Table Game
		45	AE Sexy
		46	IBCBet Live Casino
		47	BBIN
		49	Virtual Sports 3
		50	Funky Games
		51	WM
		52	ION
		55	PG Soft
		56	Joker
		57	BG
		59	GDG
		60	MaxGame
		61	Habanero
		62	CG
		65	PP Live Casino
		67	AdvantPlay
		68	AdvantPlay Mini
		69	Bitcoin
		1000 Bet Builder
		1001 Muay Thai
	*/
*/
BEGIN
	SET NOCOUNT ON

	SELECT	p.ProductID AS ProductID, p.ProductName AS ProductName
	FROM	dbo.Product3rd p WITH(NOLOCK)
	WHERE	p.ProductId NOT IN (1,3,4,6,7,9,11,12,13,14,16,17,30,33,37,38,42,43,63,66,70)

	UNION ALL
	SELECT 1000 AS ProductID, 'Bet Builder' AS ProductName

	UNION ALL
	SELECT 1001 AS ProductID, 'Muay Thai' AS ProductName

	ORDER BY  ProductID

END
GO

