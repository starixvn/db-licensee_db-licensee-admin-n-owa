USE bodb_Licensee
GO

/*<info serverAlias="DBLIC-bodb_Licensee"></info>*/
ALTER VIEW [dbo].[vw_SH_VendorSettingSel_NonConfigurable]
/*
    Created: 20250714@Danny
    DB: DBLIC.bodb_Licensee
	Description: Create view to get all Non-Configurable Vendor Setting [RedmineID: #228193]

	Example: SELECT * FROM dbo.vw_SH_VendorSettingSel_NonConfigurable
		
*/
AS

SELECT 2  AS ProductID,
N'Cash & Credit licensees:' + CHAR(13) + CHAR(10) +
N'    Other licensees: Licensing Fee * 50%' + CHAR(13) + CHAR(10) +
N'    FDL (credit Licensee of IBCIndo and 76666b): (Licensing Fee - ExtraPT) * 50%' + CHAR(13) + CHAR(10) +
N'CN88:' + CHAR(13) + CHAR(10) +
N'    1.5% of Σ Licensee WL regardless Licensee WL > or < 0' AS BillingTerms

UNION ALL

SELECT 5,
N'Cash licensees before Mar-18:' + CHAR(13) + CHAR(10) +
N'    7.5% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Cash licensees after Mar-18:' + CHAR(13) + CHAR(10) +
N'    OW: 6.5% of Σ OW Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ OW Licensee WL < 0.' + CHAR(13) + CHAR(10) +
N'    BP: 6.5% of Σ BP Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ BP Licensee WL < 0.' + CHAR(13) + CHAR(10) +
N'    ZL: 6.5% of Σ ZL Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ ZL Licensee WL < 0.' + CHAR(13) + CHAR(10) +
N'    HAIFA: 6.25% of HAIFA Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    1% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'CN88:' + CHAR(13) + CHAR(10) +
N'    1% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.'

UNION ALL

SELECT 8,
N'Licensee 12Bet:' + CHAR(13) + CHAR(10) +
N'    3.6% of 12Bet Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if 12Bet Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Other cash licensees:' + CHAR(13) + CHAR(10) +
N'    5% of Σ Other cash Licensee WL (before Aug-18)' + CHAR(13) + CHAR(10) +
N'    3.6% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Other cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    3.6% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'CN88:' + CHAR(13) + CHAR(10) +
N'    1.5% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Bobbet and Tianbo (2%):' + CHAR(13) + CHAR(10) +
N'    2% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if Licensee WL < 0.'

UNION ALL

SELECT 22,
N'For normal Macau Games' + CHAR(13) + CHAR(10) +
N'    ONEworks licensees:' + CHAR(13) + CHAR(10) +
N'        3.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'    Credit licensees:' + CHAR(13) + CHAR(10) +
N'        2% of Σ Credit Licensee WL.' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'For Blueprint''s games' + CHAR(13) + CHAR(10) +
N'    ONEworks licensees:' + CHAR(13) + CHAR(10) +
N'        4.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'    Credit licensees:' + CHAR(13) + CHAR(10) +
N'        3% of Σ Credit Licensee WL.' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ Credit Licensee WL < 0.'

UNION ALL

SELECT 27,
N'Cash licensees:' + CHAR(13) + CHAR(10) +
N'    OW: 6.5% of Σ OW Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ OW Licensee WL < 0.' + CHAR(13) + CHAR(10) +
N'    BP: 6.5% of Σ BP Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ BP Licensee WL < 0.' + CHAR(13) + CHAR(10) +
N'    ZL: 6.5% of Σ ZL Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ ZL Licensee WL < 0.' + CHAR(13) + CHAR(10) +
N'    HAIFA: 6.5% of HAIFA Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    1% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'CN88' + CHAR(13) + CHAR(10) +
N'    1% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.'

UNION ALL

SELECT 28,
N'Licensee 12Bet:' + CHAR(13) + CHAR(10) +
N'    3.6% of 12Bet Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if 12Bet Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Other cash licensees:' + CHAR(13) + CHAR(10) +
N'    5% of Σ Other cash Licensee WL (before Aug-18)' + CHAR(13) + CHAR(10) +
N'    3.6% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Other cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    3.6% of Σ Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'CN88' + CHAR(13) + CHAR(10) +
N'    1.5% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Bobbet and Tianbo (2%)' + CHAR(13) + CHAR(10) +
N'    2% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if Licensee WL < 0.'

UNION ALL

SELECT 31,
N'Cash licensees:' + CHAR(13) + CHAR(10) +
N'    Equals 10%* (Licensee WL + Full charged comm)' + CHAR(13) + CHAR(10) +
N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'     Not offer.'

UNION ALL

SELECT 34,
N'Video Poker game:' + CHAR(13) + CHAR(10) +
N'    Cash licensees:' + CHAR(13) + CHAR(10) +
N'        2.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'    Credit licensees:' + CHAR(13) + CHAR(10) +
N'        2.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Midas (Tai Xiu, Xoc Dia, Lotto3, Hi Lo, Marble Mini, RPS, Baccarat, Lucky Dash, Dragon Tiger) game:' + CHAR(13) + CHAR(10) +
N'    Credit licensees:' + CHAR(13) + CHAR(10) +
N'        3.5% of Σ Credit Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'     Cash licensees:' + CHAR(13) + CHAR(10) +
N'        3.5% of Σ Credit Licensee WL' + CHAR(13) + CHAR(10) +
N'        Do not pay if Σ Cash Licensee WL < 0.'

UNION ALL

SELECT 39,
N'For Bet Tickets:' + CHAR(13) + CHAR(10) +
N'    Cash Licensee:' + CHAR(13) + CHAR(10) +
N'        6% of Σ Cash Gross Licensee WL' + CHAR(13) + CHAR(10) +
N'        5% if Σ Cash Gross Licensee WL >= 10M CNY' + CHAR(13) + CHAR(10) +
N'            To specific, 5% if Σ Oneworks Licensee Gross WL >= 10M CNY' + CHAR(13) + CHAR(10) +
N'            To specific, 5% If Σ [Boping & Zelianta] Licensee Gross WL >= 10M CNY' + CHAR(13) + CHAR(10) +
N'        Collect from SA Gaming if Σ Cash Gross Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'    Credit licensees:' + CHAR(13) + CHAR(10) +
N'        After Jan 2025: 4.5% of (Σ Credit Gross Licensee WL - 0.8% Valid Bets Rebate)' + CHAR(13) + CHAR(10) +
N'        Before Jan 2025: 4.5% of (Σ Credit Gross Licensee WL - 1% Valid Bets Rebate)' + CHAR(13) + CHAR(10) +
N'        Collect from SA Gaming if Σ Credit Gross Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'For Tip Tickets: Tip money sharing for Money Wheel​​:' + CHAR(13) + CHAR(10) +
N'    Cash Licensee:' + CHAR(13) + CHAR(10) +
N'        SA gaming take 50% for this tip money.' + CHAR(13) + CHAR(10) +
N'        OW gets nothing for tip money' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'     Credit Licensee:' + CHAR(13) + CHAR(10) +
N'         No offer for credit'

UNION ALL

SELECT 40,
N'Licensee 12Bet:' + CHAR(13) + CHAR(10) +
N'    3.6% of 12Bet Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if 12Bet Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Other cash licensees:' + CHAR(13) + CHAR(10) +
N'    3.6% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Other cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    3.6% of Σ Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Bobbet and Tianbo (2%)' + CHAR(13) + CHAR(10) +
N'    2% of Σ Other cash Licensee WL ( from Jul 01 2020)' + CHAR(13) + CHAR(10) +
N'    Do not pay if Licensee WL < 0.'

UNION ALL

SELECT 1000,
N'4% of GGR with GGR = Σ Credit/Cash Licensee WL after Commission' + CHAR(13) + CHAR(10) +
N'Do not pay if Σ Cash and Credit Licensee Win Loss < 0'

UNION ALL

SELECT 1001,
N'Company''s cost to Muay Thai party includes:' + CHAR(13) + CHAR(10) +
N'    WL Share: WL share is fixed as 3% on WL.' + CHAR(13) + CHAR(10) +
N'    Commission Share:' + CHAR(13) + CHAR(10) +
N'        Thai partner would share with House the commission given to Super lines; based on partner''s share on total House and Partner''s PT.' + CHAR(13) + CHAR(10) +
N'        Commission share is calculated as:' + CHAR(13) + CHAR(10) +
N'            Commission share = 3/ (100 - SMA''s PT) * Commission' + CHAR(13) + CHAR(10) +
N'        Example:' + CHAR(13) + CHAR(10) +
N'            Commission = 100$' + CHAR(13) + CHAR(10) +
N'            SMA''s PT = 85%' + CHAR(13) + CHAR(10) +
N'            Commission share = 3/ (100 - 85) * 100$ = 20$' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'    Commission' + CHAR(13) + CHAR(10) +
N'        For credit licensees: depends on each super line.' + CHAR(13) + CHAR(10) +
N'        For deposit licensees:' + CHAR(13) + CHAR(10) +
N'            Non BA members: no commission' + CHAR(13) + CHAR(10) +
N'            BA members: BA comm (0.25% on turnover)' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'    SMA''s PT' + CHAR(13) + CHAR(10) +
N'        For credit licensees: depends on each super line.' + CHAR(13) + CHAR(10) +
N'        For deposit licensees:' + CHAR(13) + CHAR(10) +
N'            Non BA members: SMA''s PT = 85% (or 90% as for Tonybet)' + CHAR(13) + CHAR(10) +
N'            BA members: SMA''s PT = 0%'


UNION ALL

SELECT 6,
N'N/A - Product in-house, no billing between OW and 3rd party'

UNION ALL

SELECT 10,
N'Before Oct 2023:' + CHAR(13) + CHAR(10) +
N'ONEworks licensees:' + CHAR(13) + CHAR(10) +
N'    8% of Σ ONEworks Licensee WL, if Σ ONEworks Licensee WL <= 15mil CNY.' + CHAR(13) + CHAR(10) +
N'    7% of Σ ONEworks Licensee WL, if Σ ONEworks Licensee WL > 15mil CNY.' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ ONEworks Licensee WL < 0.' + CHAR(13) + CHAR(10) +
N'Boping + Zelianta licensees:' + CHAR(13) + CHAR(10) +
N'    8% of Σ Boping Licensee WL, if Σ Boping Licensee WL <= 2.5mil USD.' + CHAR(13) + CHAR(10) +
N'    7% of Σ Boping Licensee WL, if Σ Boping Licensee WL > 2.5mil USD.' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Boping Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +


N'After Oct 2023:' + CHAR(13) + CHAR(10) +
N'ONEworks licensees:' + CHAR(13) + CHAR(10) +
N'    7% of Σ ONEworks Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ ONEworks Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Boping + Zelianta licensees:' + CHAR(13) + CHAR(10) +
N'    7% of Σ Boping Licensee WL' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Boping Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    Do not offer.'

UNION ALL

SELECT 42,
N'N/A - Product in-house. No billing between OW and 3rd party'

UNION ALL

SELECT 43,
N'N/A'

UNION ALL

SELECT 66,
N'N/A - Product in-house. No billing between OW and 3rd party'

UNION ALL

SELECT 71,
N'N/A'

UNION ALL

SELECT 86,
N'N/A - Product in-house. No billing between OW and 3rd party'

UNION ALL

SELECT 32,
N'Cash licensees:' + CHAR(13) + CHAR(10) +
N'    5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
N'    Do not Collect from PP if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees: Progressive Billing method' + CHAR(13) + CHAR(10) +
N'    3.5% of Σ Credit Licensee WL, if Σ Credit Licensee WL <= 2mil EUR.' + CHAR(13) + CHAR(10) +
N'    3% of Σ Credit Licensee WL, if Σ Credit Licensee WL > 2mil EUR.' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
N'    Example: PaytoSupplier amount is 2.6M, then the calculation should be (2M*3.5% + 0.6M*3%)'

UNION ALL SELECT 1, N'N/A'

UNION ALL SELECT 3, N'N/A'

UNION ALL SELECT 4, 
N'Cash & Credit licensees:' + CHAR(13) + CHAR(10) +
N'    40% of what is profit/loss after operation' + CHAR(13) + CHAR(10) +
N'    Include extra PT' + CHAR(13) + CHAR(10) +
N'    Include server cost & operation cost' 

UNION ALL SELECT 7, N'N/A'

UNION ALL SELECT 9, N'N/A'

UNION ALL SELECT 11, 
N'ONEworks licensees:' + CHAR(13) + CHAR(10) +
N'    5% of Σ ONEworks Licensee WL.' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ ONEworks Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Boping + Zelianta licensees:' + CHAR(13) + CHAR(10) +
N'    5% of Σ Boping Licensee WL.' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Boping Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Bidme Tips:' + CHAR(13) + CHAR(10) +
N'    60% of Σ Bidme Tips amount' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees - Before [Dec-2016]:' + CHAR(13) + CHAR(10) +
N'    2% of Σ Credit Licensee WL.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees - After [Dec-2016]:' + CHAR(13) + CHAR(10) +
N'    3.5% of (Σ Credit Licensee WL less 1% of Σ Credit Valid Bet Amount).'

UNION ALL SELECT 13, N'N/A'

UNION ALL SELECT 14, 
N'PROGRESSIVE FEE is the amount that licensee settles with Microgaming (ONEworks is middle man), on progressive games, including contribution and member winnings.' + CHAR(13) + CHAR(10) +
N'    PROGRESSIVE FEE = (Generic Contribution - Generic Payout) + (Branded Contribution - Branded Payout)' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'GENERIC GAMES FEE is the fee that ONEworks pays to Microgaming to operate all generic games, both Live and RNG Casino.' + CHAR(13) + CHAR(10) +
N'    BRANDED GAMES FEE is the fee that ONEworks pays to Microgaming to operate all branded games, both Live and RNG Casino.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Amount pay to Microgaming = GENERIC GAMES FEE + BRANDED GAMES FEE + PROGRESSIVE FEE' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'GENERIC GAMES FEE =' + CHAR(13) + CHAR(10) +
N'    IF (Generic Live + Generic RNG – Generic Contribution) ≤ 2m USD THEN' + CHAR(13) + CHAR(10) +
N'            (Generic Live + Generic RNG – Generic Contribution) x 10%' + CHAR(13) + CHAR(10) +
N'    ELSE' + CHAR(13) + CHAR(10) +
N'            2m USD x 10% + ((Generic Live + Generic RNG – Generic Contribution) - 2m USD) x 8%' + CHAR(13) + CHAR(10) +
N'    If GENERIC GAMES FEE ≤ 0 then equals 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'BRANDED GAMES FEE = (Branded Live + Branded RNG - Branded Contribution) x 17.5%' + CHAR(13) + CHAR(10) +
N'     If BRANDED GAMES FEE ≤ 0 then equals 0.'

UNION ALL SELECT 15, N'N/A'

UNION ALL SELECT 16, N'N/A'

UNION ALL SELECT 17,
N'PROGRESSIVE FEE is the amount that licensee settles with Microgaming (ONEworks is middle man), on progressive games, including contribution and member winnings.' + CHAR(13) + CHAR(10) +
N'    PROGRESSIVE FEE = (Generic Contribution - Generic Payout) + (Branded Contribution - Branded Payout)' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'GENERIC GAMES FEE is the fee that ONEworks pays to Microgaming to operate all generic games, both Live and RNG Casino.' + CHAR(13) + CHAR(10) +
N'    BRANDED GAMES FEE is the fee that ONEworks pays to Microgaming to operate all branded games, both Live and RNG Casino.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Amount pay to Microgaming = GENERIC GAMES FEE + BRANDED GAMES FEE + PROGRESSIVE FEE' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'GENERIC GAMES FEE =' + CHAR(13) + CHAR(10) +
N'    IF (Generic Live + Generic RNG – Generic Contribution) ≤ 2m USD THEN' + CHAR(13) + CHAR(10) +
N'            (Generic Live + Generic RNG – Generic Contribution) x 10%' + CHAR(13) + CHAR(10) +
N'    ELSE' + CHAR(13) + CHAR(10) +
N'            2m USD x 10% + ((Generic Live + Generic RNG – Generic Contribution) - 2m USD) x 8%' + CHAR(13) + CHAR(10) +
N'    If GENERIC GAMES FEE ≤ 0 then equals 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'BRANDED GAMES FEE = (Branded Live + Branded RNG - Branded Contribution) x 17.5%' + CHAR(13) + CHAR(10) +
N'     If BRANDED GAMES FEE ≤ 0 then equals 0.'

UNION ALL SELECT 23,
N'Cash & Credit licensees:' + CHAR(13) + CHAR(10) +
N'    50% of what is profit/loss after operation' + CHAR(13) + CHAR(10) +
N'			  Include extra PT' + CHAR(13) + CHAR(10) +
N'            Include server cost & operation cost'

UNION ALL SELECT 25, 
N'Cash licensees:' + CHAR(13) + CHAR(10) +
N'     -1.5% of Sportsbook Buyback amount.' + CHAR(13) + CHAR(10) +
N'     100% of WL on Buyback transactions.' + CHAR(13) + CHAR(10) +
N'     100% of WL on bought tickets.'

UNION ALL SELECT 30, 
N'Company''s cost to Bull Fighting party includes:' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'WL Share: WL share is fixed as 8% on WL.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Commission Share: Bull Fighting partner would share with House the commission given to Super lines; based on partner''s share on total House and Partner''s PT.' + CHAR(13) + CHAR(10) +
N'Commission share is calculated as:' + CHAR(13) + CHAR(10) +
N'    Commission share = 8 / (100 - SMA''s PT) * Commission' + CHAR(13) + CHAR(10) +
N'Example:' + CHAR(13) + CHAR(10) +
N'    Commission = 100$' + CHAR(13) + CHAR(10) +
N'    SMA''s PT = 85%' + CHAR(13) + CHAR(10) +
N'    Commission share = 8 / (100 - 85) * 100$ = 20$' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Commission' + CHAR(13) + CHAR(10) +
N'    For credit licensees: depends on each super line.' + CHAR(13) + CHAR(10) +
N'    For deposit licensees:' + CHAR(13) + CHAR(10) +
N'			  Non BA members: no commission' + CHAR(13) + CHAR(10) +
N'			  BA members: BA comm (0.25% on turnover)' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'SMA''s PT' + CHAR(13) + CHAR(10) +
N'    For credit licensees: depends on each super line.' + CHAR(13) + CHAR(10) +
N'    For deposit licensees:' + CHAR(13) + CHAR(10) +
N'			  Non BA members: SMA''s PT = 85% (or 90% as for Tonybet)' + CHAR(13) + CHAR(10) +
N'			  BA members: SMA''s PT = 0%'

UNION ALL SELECT 33,
N'Cash licensees: Not offer' + CHAR(13) + CHAR(10) +
N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    4% of Rake Commission, Gem Bought, and Insurance Win loss.'

UNION ALL SELECT 63,
N'N/A - Product in-house. No billing between OW and 3rd party'

UNION ALL SELECT 38, N'N/A - Product in-house, no billing between OW and 3rd party'

UNION ALL SELECT 72, N'N/A - Product in-house, no billing between OW and 3rd party'

UNION ALL SELECT 102, N'N/A - Product in-house, no billing between OW and 3rd party'

UNION ALL

SELECT 21,
N'Cash licensees:' + CHAR(13) + CHAR(10) +
N'    4% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
N'    Collect from AllBet if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    5% of (Σ Credit Licensee WL less 1% of Σ Credit Licensee Valid Bet Amount).' + CHAR(13) + CHAR(10) +
N'    Collect from AllBet if Σ Credit Licensee WL < 0.'


UNION ALL

SELECT 59,
N'Cash licensees:' + CHAR(13) + CHAR(10) +
N'    5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
N'    Collect from GDG if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    3.5% of (Σ Credit Licensee WL less 1% of Σ Credit Licensee Valid Bet Amount).' + CHAR(13) + CHAR(10) +
N'    Collect from GDG if Σ Credit Licensee WL < 0.'


UNION ALL

SELECT 65,
N'Cash licensees:' + CHAR(13) + CHAR(10) +
N'    Not offer' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    After Dec 2024:' + CHAR(13) + CHAR(10) +
N'			   6.5% * (Σ Credit Licensee WL - 0.5% valid bets rebate)' + CHAR(13) + CHAR(10) +
N'    Before Dec 2024: Progressive Billing method' + CHAR(13) + CHAR(10) +
N'			   6.5% of Σ Credit Licensee WL, if Σ Credit Licensee WL <= 2mil USD.' + CHAR(13) + CHAR(10) +
N'			   6% of Σ Credit Licensee WL, if 2mil USD < Σ Credit Licensee WL <= 5mil USD.' + CHAR(13) + CHAR(10) +
N'			   5% of Σ Credit Licensee WL, if Σ Credit Licensee WL > 5mil USD.' + CHAR(13) + CHAR(10) +
N'             Do not pay if Σ Credit Licensee WL < 0.'

UNION ALL
SELECT 12,

N'ONEworks licensees:' + CHAR(13) + CHAR(10) +
N'    3.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
N'    Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
N'Credit licensees:' + CHAR(13) + CHAR(10) +
N'    Do not offer'


GO



