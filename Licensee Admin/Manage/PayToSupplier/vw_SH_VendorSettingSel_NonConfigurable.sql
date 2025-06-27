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
'Cash & Credit licensees:' + CHAR(13) + CHAR(10) +
'    Other licensees: Licensing Fee * 50%' + CHAR(13) + CHAR(10) +
'    FDL (credit Licensee of IBCIndo and 76666b): (Licensing Fee - ExtraPT) * 50%' + CHAR(13) + CHAR(10) +
'CN88:' + CHAR(13) + CHAR(10) +
'    1.5% of Σ Licensee WL regardless Licensee WL > or < 0' AS BillingTerms

UNION ALL

SELECT 5,
'Cash licensees before Mar-18:' + CHAR(13) + CHAR(10) +
'    7.5% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Cash licensees after Mar-18:' + CHAR(13) + CHAR(10) +
'    OW: 6.5% of Σ OW Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ OW Licensee WL < 0.' + CHAR(13) + CHAR(10) +
'    BP: 6.5% of Σ BP Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ BP Licensee WL < 0.' + CHAR(13) + CHAR(10) +
'    ZL: 6.5% of Σ ZL Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ ZL Licensee WL < 0.' + CHAR(13) + CHAR(10) +
'    HAIFA: 6.25% of HAIFA Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Credit licensees:' + CHAR(13) + CHAR(10) +
'    1% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'CN88:' + CHAR(13) + CHAR(10) +
'    1% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.'

UNION ALL

SELECT 8,
 'Licensee 12Bet:' + CHAR(13) + CHAR(10) +
'    3.6% of 12Bet Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if 12Bet Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Other cash licensees:' + CHAR(13) + CHAR(10) +
'    5% of Σ Other cash Licensee WL (before Aug-18)' + CHAR(13) + CHAR(10) +
'    3.6% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Other cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Credit licensees:' + CHAR(13) + CHAR(10) +
'    3.6% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'CN88:' + CHAR(13) + CHAR(10) +
'    1.5% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Bobbet and Tianbo (2%):' + CHAR(13) + CHAR(10) +
'    2% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if Licensee WL < 0.'

UNION ALL

SELECT 22,
'For normal Macau Games' + CHAR(13) + CHAR(10) +
'    ONEworks licensees:' + CHAR(13) + CHAR(10) +
'        3.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'    Credit licensees:' + CHAR(13) + CHAR(10) +
'        2% of Σ Credit Licensee WL.' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'For Blueprint''s games' + CHAR(13) + CHAR(10) +
'    ONEworks licensees:' + CHAR(13) + CHAR(10) +
'        4.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'    Credit licensees:' + CHAR(13) + CHAR(10) +
'        3% of Σ Credit Licensee WL.' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ Credit Licensee WL < 0.'

UNION ALL

SELECT 27,
'Cash licensees:' + CHAR(13) + CHAR(10) +
'    OW: 6.5% of Σ OW Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ OW Licensee WL < 0.' + CHAR(13) + CHAR(10) +
'    BP: 6.5% of Σ BP Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ BP Licensee WL < 0.' + CHAR(13) + CHAR(10) +
'    ZL: 6.5% of Σ ZL Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ ZL Licensee WL < 0.' + CHAR(13) + CHAR(10) +
'    HAIFA: 6.5% of HAIFA Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Credit licensees:' + CHAR(13) + CHAR(10) +
'    1% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'CN88' + CHAR(13) + CHAR(10) +
'    1% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.'

UNION ALL

SELECT 28,
'Licensee 12Bet:' + CHAR(13) + CHAR(10) +
'    3.6% of 12Bet Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if 12Bet Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Other cash licensees:' + CHAR(13) + CHAR(10) +
'    5% of Σ Other cash Licensee WL (before Aug-18)' + CHAR(13) + CHAR(10) +
'    3.6% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Other cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Credit licensees:' + CHAR(13) + CHAR(10) +
'    3.6% of Σ Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'CN88' + CHAR(13) + CHAR(10) +
'    1.5% of Σ Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Bobbet and Tianbo (2%)' + CHAR(13) + CHAR(10) +
'    2% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if Licensee WL < 0.'

UNION ALL

SELECT 31,
'Cash licensees:' + CHAR(13) + CHAR(10) +
'    Equals 10%* (Licensee WL + Full charged comm)' + CHAR(13) + CHAR(10) +
'Credit licensees:' + CHAR(13) + CHAR(10) +
'     Not offer.'

UNION ALL

SELECT 34,
'Video Poker game:' + CHAR(13) + CHAR(10) +
'    Cash licensees:' + CHAR(13) + CHAR(10) +
'        2.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'    Credit licensees:' + CHAR(13) + CHAR(10) +
'        2.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Midas (Tai Xiu, Xoc Dia, Lotto3, Hi Lo, Marble Mini, RPS, Baccarat, Lucky Dash, Dragon Tiger) game:' + CHAR(13) + CHAR(10) +
'    Credit licensees:' + CHAR(13) + CHAR(10) +
'        3.5% of Σ Credit Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'     Cash licensees:' + CHAR(13) + CHAR(10) +
'        3.5% of Σ Credit Licensee WL' + CHAR(13) + CHAR(10) +
'        Do not pay if Σ Cash Licensee WL < 0.'

UNION ALL

SELECT 36,
'ONEworks licensees:' + CHAR(13) + CHAR(10) +
'    3.5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Credit licensees:' + CHAR(13) + CHAR(10) +
'    3.5% of Σ Credit Licensee WL.' + CHAR(13) + CHAR(10) +
'    Do not collect/pay if Σ Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'For SG Jackpot Prize' + CHAR(13) + CHAR(10) +
'    House is in charge of paying this amount in advance. Then Jackpot prize is deducted together with Contribution when billing with SG vendor.'

UNION ALL

SELECT 39,
'For Bet Tickets:' + CHAR(13) + CHAR(10) +
'    Cash Licensee:' + CHAR(13) + CHAR(10) +
'        6% of Σ Cash Gross Licensee WL' + CHAR(13) + CHAR(10) +
'        5% if Σ Cash Gross Licensee WL >= 10M CNY' + CHAR(13) + CHAR(10) +
'            To specific, 5% if Σ Oneworks Licensee Gross WL >= 10M CNY' + CHAR(13) + CHAR(10) +
'            To specific, 5% If Σ [Boping & Zelianta] Licensee Gross WL >= 10M CNY' + CHAR(13) + CHAR(10) +
'        Collect from SA Gaming if Σ Cash Gross Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'    Credit licensees:' + CHAR(13) + CHAR(10) +
'        After Jan 2025: 4.5% of (Σ Credit Gross Licensee WL - 0.8% Valid Bets Rebate)' + CHAR(13) + CHAR(10) +
'        Before Jan 2025: 4.5% of (Σ Credit Gross Licensee WL - 1% Valid Bets Rebate)' + CHAR(13) + CHAR(10) +
'        Collect from SA Gaming if Σ Credit Gross Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'For Tip Tickets: Tip money sharing for Money Wheel​​:' + CHAR(13) + CHAR(10) +
'    Cash Licensee:' + CHAR(13) + CHAR(10) +
'        SA gaming take 50% for this tip money.' + CHAR(13) + CHAR(10) +
'        OW gets nothing for tip money' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'     Credit Licensee:' + CHAR(13) + CHAR(10) +
'         No offer for credit'

UNION ALL

SELECT 40,
'Licensee 12Bet:' + CHAR(13) + CHAR(10) +
'    3.6% of 12Bet Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if 12Bet Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Other cash licensees:' + CHAR(13) + CHAR(10) +
'    3.6% of Σ Other cash Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Other cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Credit licensees:' + CHAR(13) + CHAR(10) +
'    3.6% of Σ Licensee WL (from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Bobbet and Tianbo (2%)' + CHAR(13) + CHAR(10) +
'    2% of Σ Other cash Licensee WL ( from Jul 01 2020)' + CHAR(13) + CHAR(10) +
'    Do not pay if Licensee WL < 0.'

UNION ALL

SELECT 77,
'For Bet Tickets:' + CHAR(13) + CHAR(10) +
'    Cash Licensee:' + CHAR(13) + CHAR(10) +
'        6% of Σ Cash Gross Licensee WL' + CHAR(13) + CHAR(10) +
'        5% if Σ Cash Gross Licensee WL >= 10M CNY' + CHAR(13) + CHAR(10) +
'            To specific, 5% if Σ Oneworks Licensee Gross WL >= 10M CNY' + CHAR(13) + CHAR(10) +
'            To specific, 5% If Σ [Boping & Zelianta] Licensee Gross WL >= 10M CNY' + CHAR(13) + CHAR(10) +
'        Collect from SA Gaming if Σ Cash Gross Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'    Credit licensees:' + CHAR(13) + CHAR(10) +
'        After Jan 2025: 4.5% of (Σ Credit Gross Licensee WL - 0.8% Valid Bets Rebate)' + CHAR(13) + CHAR(10) +
'        Before Jan 2025: 4.5% of (Σ Credit Gross Licensee WL - 1% Valid Bets Rebate)' + CHAR(13) + CHAR(10) +
'        Collect from SA Gaming if Σ Credit Gross Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'For Tip Tickets: Tip money sharing for Money Wheel​​:' + CHAR(13) + CHAR(10) +
'    Cash Licensee:' + CHAR(13) + CHAR(10) +
'        SA gaming take 50% for this tip money.' + CHAR(13) + CHAR(10) +
'        OW gets nothing for tip money' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'     Credit Licensee:' + CHAR(13) + CHAR(10) +
'         No offer for credit'

UNION ALL

SELECT 1000,
'4% of GGR with GGR = Σ Credit/Cash Licensee WL after Commission' + CHAR(13) + CHAR(10) +
'Do not pay if Σ Cash and Credit Licensee Win Loss < 0'

UNION ALL

SELECT 1001,
'Company''s cost to Muay Thai party includes:' + CHAR(13) + CHAR(10) +
'    WL Share: WL share is fixed as 3% on WL.' + CHAR(13) + CHAR(10) +
'    Commission Share:' + CHAR(13) + CHAR(10) +
'        Thai partner would share with House the commission given to Super lines; based on partner''s share on total House and Partner''s PT.' + CHAR(13) + CHAR(10) +
'        Commission share is calculated as:' + CHAR(13) + CHAR(10) +
'            Commission share = 3/ (100 - SMA''s PT) * Commission' + CHAR(13) + CHAR(10) +
'        Example:' + CHAR(13) + CHAR(10) +
'            Commission = 100$' + CHAR(13) + CHAR(10) +
'            SMA''s PT = 85%' + CHAR(13) + CHAR(10) +
'            Commission share = 3/ (100 - 85) * 100$ = 20$' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'    Commission' + CHAR(13) + CHAR(10) +
'        For credit licensees: depends on each super line.' + CHAR(13) + CHAR(10) +
'        For deposit licensees:' + CHAR(13) + CHAR(10) +
'            Non BA members: no commission' + CHAR(13) + CHAR(10) +
'            BA members: BA comm (0.25% on turnover)' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'    SMA''s PT' + CHAR(13) + CHAR(10) +
'        For credit licensees: depends on each super line.' + CHAR(13) + CHAR(10) +
'        For deposit licensees:' + CHAR(13) + CHAR(10) +
'            Non BA members: SMA''s PT = 85% (or 90% as for Tonybet)' + CHAR(13) + CHAR(10) +
'            BA members: SMA''s PT = 0%'


UNION ALL

SELECT 6,
'N/A - Product in-house, no billing between OW and 3rd party'

UNION ALL

SELECT 10,
'ONEworks licensees:' + CHAR(13) + CHAR(10) +
'    7% of Σ ONEworks Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ ONEworks Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Boping + Zelianta licensees:' + CHAR(13) + CHAR(10) +
'    7% of Σ Boping Licensee WL' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Boping Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Credit licensees:' + CHAR(13) + CHAR(10) +
'    Do not offer.'

UNION ALL

SELECT 42,
'There no billing with 3rd for this product (100% will go to 1W)'

UNION ALL

SELECT 43,
'N/A'

UNION ALL

SELECT 47,
'Cash Licensee' + CHAR(13) + CHAR(10) +
'    No offer to Cash' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Credit Licensee' + CHAR(13) + CHAR(10) +
'    4% of Σ Credit Gross Licensee WL' + CHAR(13) + CHAR(10) +
'    Collect from BBIN if Σ Credit Gross Licensee WL < 0.'


UNION ALL

SELECT 66,
'There no billing with 3rd for this product (100% will go to 1W)'

UNION ALL

SELECT 69,
'N/A'

UNION ALL

SELECT 71,
'N/A'

UNION ALL

SELECT 86,
'There no billing with 3rd for this product (100% will go to 1W)'

UNION ALL

SELECT 32,
'Cash licensees:' + CHAR(13) + CHAR(10) +
'    5% of Σ Cash Licensee WL.' + CHAR(13) + CHAR(10) +
'    Do not Collect from PP if Σ Cash Licensee WL < 0.' + CHAR(13) + CHAR(10) +
CHAR(13) + CHAR(10) +

'Credit licensees: Progressive Billing method' + CHAR(13) + CHAR(10) +
'    3.5% of Σ Credit Licensee WL, if Σ Credit Licensee WL <= 2mil EUR.' + CHAR(13) + CHAR(10) +
'    3% of Σ Credit Licensee WL, if Σ Credit Licensee WL > 2mil EUR.' + CHAR(13) + CHAR(10) +
'    Do not pay if Σ Credit Licensee WL < 0.' + CHAR(13) + CHAR(10) +
'    Example: PaytoSupplier amount is 2.6M, then the calculation should be (2M*3.5% + 0.6M*3%)'

GO



