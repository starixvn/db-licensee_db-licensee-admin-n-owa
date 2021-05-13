/*<info serverAlias="DBCUST-bodb_Licensee"></info>*/

/*
	Created: 20210512@Percy
	DB: DBCUST-bodb_Licensee
	Task: Remove Licensee Code setting of some parties: Hong88,Jarvis,Taipanbet,Jinyazhou,Titancraft
*/

use bodb_Licensee
go

/*
	select * from dbo.OAS_Party with (nolock)
	where PartyId in (238,261,330,411,443)

	Hong88
	Jarvis
	Taipanbet
	Jinyazhou
	Titancraft
*/

delete dbo.OAS_PartyBaseCurrency with (rowlock, updlock)
where PartyId in (238,261,330,411,443)
	and BaseCurrencyId = 13 -- CNY