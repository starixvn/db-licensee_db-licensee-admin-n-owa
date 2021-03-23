/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210314@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Update Todate for all terminated licensees
*/
USE bodb_Licensee 
GO

PRINT 'Prepare Terminated Licensee List: 77 records'
DECLARE @TerminatedLicenseeTable TABLE(PartyID INT, PartyName VARCHAR(50), LicenseeCode VARCHAR(50))
INSERT INTO @TerminatedLicenseeTable(PartyID, PartyName, LicenseeCode)
VALUES
		(279, 	'108bet', 	'PHL-LSEE-108BET EUR') 	
		,(284, 	'10BET', 	'PHL-LSEE-10BET EUR') 	
		,(61, 	'67BET', 	'PHL-LSEE-67BET EUR') 	
		,(70, 	'28BET', 	'PHL-LSEE-28Bet EUR') 	
		,(89, 	'666VIP', 	'PHL-LSEE-666VIP EUR') 	
		,(148, 	'21Cash', 	'PHL-LSEE-21cash EUR') 	
		,(39, 	'Avia', 	'PHL-LSEE-AVIA EUR') 	
		,(67, 	'Allbetclub', 	'PHL-LSEE-All Bet Club EUR') 	
		,(142, 	'Asianbet', 	'PHL-LSEE-Asianbet EUR') 	
		,(117, 	'Baobet', 	'PHL-LSEE-Baobet EUR') 	
		,(249, 	'Aragon88', 	'PHL-LSEE-Aragon88 EUR') 	
		,(233, 	'ABB688', 	'PHL-LSEE-ABB688 EUR') 	
		,(281, 	'99UU', 	'PHL-LSEE-99UU EUR') 	
		,(287, 	'AK318', 	'PHL-LSEE-AK318 EUR') 	
		,(20, 	'DELA', 	'PHL-LSEE-1BET EUR') 	
		,(35, 	'Bwinning', 	'PHL-LSEE-BWINNING EUR') 	
		,(58, 	'Bet2day', 	'PHL-LSEE-Bet2day EUR') 	
		,(76, 	'DAYWIN', 	'PHL-LSEE-DAYWIN EUR') 	
		,(97, 	'Doctorgame', 	'PHL-LSEE-Doctorgame EUR') 	
		,(114, 	'Empire555', 	'PHL-LSEE-Empire555 EUR') 	
		,(115, 	'DUOLE', 	'PHL-LSEE-Duole EUR') 	
		,(153, 	'CQ11', 	'PHL-LSEE-CQ11 EUR') 	
		,(217, 	'Emmyo', 	'PHL-LSEE-Emmyo EUR') 	
		,(222, 	'GDC', 	'PHL-LSEE-GDC EUR') 	
		,(246, 	'BetStar', 	'PHL-LSEE-BETSTAR EUR') 	
		,(241, 	'BuyWin', 	'PHL-LSEE-BUYWIN EUR') 	
		,(268, 	'GOAB88', 	'PHL-LSEE-GOAB88 EUR') 	
		,(291, 	'Citybk', 	'PHL-LSEE-CITYBK EUR') 	
		,(309, 	'Fugui', 	'PHL-LSEE-FUGUI EUR') 	
		,(22, 	'MayFair', 	'PHL-LSEE-BET16 EUR') 	
		,(29, 	'Tycoon', 	'PHL-LSEE-TYCOON EUR') 	
		,(37, 	'Livebet365', 	'PHL-LSEE-LIVEBET365 EUR') 	
		,(38, 	'i668bet', 	'PHL-LSEE-i668bet EUR') 	
		,(64, 	'Mgm88', 	'PHL-LSEE-Mgm88 EUR') 	
		,(62, 	'Hbobet', 	'PHL-LSEE-Hbobet EUR') 	
		,(42, 	'SLC88', 	'PHL-LSEE-Smart TV EUR') 	
		,(77, 	'Royalebet', 	'PHL-LSEE-Royalebet95 EUR') 	
		,(44, 	'Saloncs', 	'PHL-LSEE-SalonCS EUR') 	
		,(48, 	'K8', 	'PHL-LSEE-K8 EUR') 	
		,(81, 	'GooBet', 	'PHL-LSEE-GOOBET EUR') 	
		,(79, 	'KaiHao', 	'PHL-LSEE-KaiHao EUR') 	
		,(86, 	'SHABAING', 	'PHL-LSEE-SHABAing EUR') 	
		,(69, 	'THBET', 	'PHL-LSEE-THBet EUR') 	
		,(55, 	'Tonybet', 	'PHL-LSEE-Tonybet EUR') 	
		,(92, 	'Inbet', 	'PHL-LSEE-Inbet88 EUR') 	
		,(93, 	'MarvelDH', 	'PHL-LSEE-MarvelDH EUR') 	
		,(150, 	'Lexibet', 	'PHL-LSEE-Lexibet EUR') 	
		,(146, 	'King10', 	'PHL-LSEE-King10 EUR') 	
		,(257, 	'sbcbet', 	'PHL-LSEE-Sbcbet EUR') 	
		,(185, 	'Uwin18', 	'PHL-LSEE-Uwin18 EUR') 	
		,(186, 	'Platinum', 	'PHL-LSEE-Platinum EUR') 	
		,(250, 	'TCL', 	'PHL-LSEE-TCL EUR') 	
		,(235, 	'Indowin', 	'PHL-LSEE-Indowin EUR') 	
		,(240, 	'Kasking88', 	'PHL-LSEE-KASKING EUR') 	
		,(237, 	'Star99', 	'PHL-LSEE-STAR99 EUR') 	
		,(265, 	'LongBao', 	'PHL-LSEE-LONGBAO EUR') 	
		,(252, 	'MrCat', 	'PHL-LSEE-MRCAT EUR') 	
		,(277, 	'Holey', 	'PHL-LSEE-HOLEY EUR') 	
		,(267, 	'SSSSEA', 	'PHL-LSEE-SSSSEA EUR') 	
		,(314, 	'jinmangguo', 	'PHL-LSEE-JINMANGGUO EUR') 	
		,(313, 	'Haoying', 	'PHL-LSEE-HAOYING EUR') 	
		,(33, 	'VCasia', 	'phl-lsee-vcasia eur') 	
		,(63, 	'Winner99', 	'PHL-LSEE-Winner99 EUR') 	
		,(90, 	'YHY1980', 	'PHL-LSEE-YHY1980 EUR') 	
		,(171, 	'Webet138', 	'PHL-LSEE-Webet138 EUR') 	
		,(264, 	'Wuming', 	'PHL-LSEE-WUMING EUR') 	
		,(280, 	'WM8888', 	'PHL-LSEE-WM8888 EUR') 	
		,(300, 	'VGS', 	'PHL-LSEE-VGS EUR') 	
		,(369, 	'Win68Club', 	'PHL-LSEE-WIN68CLUB EUR') 	
		,(318, 	'GWORLD', 	'PHL-LSEE-GWORLD EUR') 	
		,(343, 	'laba360', 	'PHL-LSEE-LABA360 EUR') 	
		,(397, 	'shicaigw', 	'PHL-LSEE-SHICAIGW EUR') 	
		,(136, 	'TooBet', 	'PHL-LSEE-Toobet EUR') 	
		,(234, 	'Ty777', 	'PHL-LSEE-TY777 EUR') 	
		,(27, 	'Vwin', 	'PHL-LSEE-VWIN EUR') 	
		,(167, 	'WeBet168', 	'PHL-LSEE-Webet168 EUR') 	
		,(393, 	'WinWin', 	'PHL-LSEE-WINWIN EUR') 	

PRINT 'Update Todate for all terminated licensees'
UPDATE p
	SET ToDate = '2019-08-31'
FROM @TerminatedLicenseeTable t
	INNER JOIN OAS_PartyBaseCurrency p WITH(NOLOCK) ON t.PartyID = p.PartyID AND p.LicenseeCode = t.LicenseeCode
WHERE p.ToDate = '2050-01-01'